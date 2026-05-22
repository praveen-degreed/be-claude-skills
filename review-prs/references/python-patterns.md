# Python/FastAPI/Async Anti-Pattern Reference

Decision trees and anti-patterns for Python 3.12 + FastAPI + async development.

---

## Async Decision Tree

```
Is the operation I/O-bound?
|
+-- YES --> Use async/await
|   |
|   +-- Multiple independent calls? --> asyncio.gather()
|   +-- Need timeout? --> asyncio.timeout() (Python 3.11+, preferred)
|   |                     asyncio.wait_for() (older, still works)
|   +-- Need to wait? --> await asyncio.sleep() (NEVER time.sleep())
|   +-- Need background? --> asyncio.create_task() with strong ref + done_callback
|   +-- Need structured concurrency? --> asyncio.TaskGroup() (Python 3.11+)
|   +-- Need to cancel? --> task.cancel() + await with try/except CancelledError
|
+-- NO (CPU-bound) --> Use loop.run_in_executor(None, func)
    |
    +-- Heavy CPU (>100ms)? --> ThreadPoolExecutor or ProcessPoolExecutor
    +-- Quick CPU (<100ms)? --> Just run it (overhead of executor not worth it)
```

## Error Handling Decision Tree

```
Caught an exception?
|
+-- External call (Redis/LLM/HTTP)?
|   +-- Recoverable? --> log_warn + retry or fallback
|   +-- Not recoverable? --> log_error(e=exc) + raise HTTPException(500)
|
+-- Validation error?
|   +-- Request validation --> HTTPException(400, detail="specific message")
|   +-- LLM output validation --> retry with error feedback (up to 3 attempts)
|
+-- Auth/access error?
|   +-- Use specific SecurityValidationError subclass
|
+-- Unknown?
    +-- log_error(e=exc) + raise HTTPException(500, detail="Internal error")

NEVER: except: pass
NEVER: except Exception: return None
NEVER: raise HTTPException(detail=str(e))  # Leaks internals
```

## LLM Output Decision Tree

```
Need structured data from LLM?
|
+-- YES --> Use Pydantic model with response_format=
|   |
|   +-- Model exists in ai_structured_outputs.py? --> Reuse it
|   +-- New model needed? --> Add to ai_structured_outputs.py with Field(description=)
|   +-- Validation fails? --> Retry with error feedback (max 3 attempts)
|
+-- NO (free-form text)
    +-- Streaming? --> sanitize_markdown() on each yielded chunk or final response
    +-- Non-streaming? --> sanitize_markdown() before returning
```

## Prompt Security Decision Tree

```
Adding user-controlled data to LLM prompt?
|
+-- Is it going into the system message?
|   +-- YES --> STOP. Move to user message with <context> delimiters.
|   +-- NO, it's in the user message
|       +-- Is it wrapped in delimiters? (<context>...</context>)
|       |   +-- YES --> OK, but add length limit
|       |   +-- NO --> Add delimiters
|       +-- Is it sanitized?
|           +-- YES (regex patterns, encoding detection) --> OK
|           +-- NO --> Add sanitization
|
+-- Is it RAG content from uploaded documents?
|   +-- Was the document scanned for injection at upload time?
|   |   +-- YES --> Place in user message with <reference> delimiters
|   |   +-- NO --> FLAG: document content is untrusted
|   +-- Is it in system or user role?
|       +-- System --> MOVE to user role
|       +-- User with delimiters --> OK
|
+-- Is it conversation history?
    +-- Is there a message count/token limit?
    |   +-- YES --> OK
    |   +-- NO --> FLAG: unbounded history growth
    +-- Are old messages from the user validated?
        +-- Not needed if using proper message roles
```

## Memory Decision Tree

```
Creating a new collection (list, dict, set)?
|
+-- Is it at module/class level (global state)?
|   +-- YES --> Does it have a size limit?
|       +-- YES (maxlen, maxsize, TTL) --> OK
|       +-- NO --> FLAG: unbounded global state
|
+-- Is it per-request?
|   +-- YES --> Will it grow with input size?
|       +-- YES --> Is there a cap?
|       |   +-- YES --> OK (e.g., chunk_text[:2000])
|       |   +-- NO --> FLAG: input-proportional memory
|       +-- NO --> OK
|
+-- Is it accumulating across requests?
    +-- YES --> FLAG: memory leak
    +-- NO --> OK
```

---

## Common Anti-Patterns with Fixes

### 1. Blocking in Async

```python
# ANTI-PATTERN: Blocks the entire event loop
async def process():
    time.sleep(5)                    # Blocks all other requests!
    data = requests.get(url)         # Blocks!
    with open(path) as f:            # Blocks!
        content = f.read()

# FIX:
async def process():
    await asyncio.sleep(5)
    async with httpx.AsyncClient() as client:
        data = await client.get(url)
    async with aiofiles.open(path) as f:
        content = await f.read()
```

### 2. Fire-and-Forget Tasks

```python
# ANTI-PATTERN: Task may be garbage collected in Python 3.12+
asyncio.create_task(save_to_redis(data))

# FIX: Keep strong reference
_background_tasks: set[asyncio.Task] = set()

task = asyncio.create_task(save_to_redis(data))
_background_tasks.add(task)
task.add_done_callback(_background_tasks.discard)

# BEST: Use TaskGroup (Python 3.11+)
async with asyncio.TaskGroup() as tg:
    tg.create_task(save_to_redis(data))
    tg.create_task(send_notification(user))
```

### 3. N+1 Redis Calls

```python
# ANTI-PATTERN: One round-trip per key
results = []
for key in keys:
    val = await redis.get(key)    # N round-trips
    results.append(val)

# FIX: Use pipeline (1 round-trip)
async with redis.pipeline() as pipe:
    for key in keys:
        pipe.get(key)
    results = await pipe.execute()
```

### 4. String Concatenation in Loop

```python
# ANTI-PATTERN: O(n^2) due to string immutability
response = ""
async for chunk in stream:
    response += chunk.content       # Creates new string each time

# FIX: O(n) with list + join
chunks = []
async for chunk in stream:
    chunks.append(chunk.content)
response = "".join(chunks)
```

### 5. Unbounded Conversation History

```python
# ANTI-PATTERN: Sends ALL messages to LLM
messages = [{"role": "system", "content": system_prompt}]
messages.extend(all_previous_messages)  # Could be 1000+ messages
messages.append({"role": "user", "content": query})

# FIX: Limit context window
from collections import deque
MAX_HISTORY = 20
recent = deque(all_previous_messages, maxlen=MAX_HISTORY)
messages = [{"role": "system", "content": system_prompt}]
messages.extend(recent)
messages.append({"role": "user", "content": query})
```

### 6. Raw JSON Parsing of LLM Output

```python
# ANTI-PATTERN: No schema validation, crashes on malformed output
response = await client.chat.completions.create(messages=messages)
data = json.loads(response.choices[0].message.content)
summary = data["summary"]  # KeyError if field missing

# FIX: Structured output with retry
from app.models.ai_structured_outputs import ConversationSummary

for attempt in range(3):
    try:
        response = await client.beta.chat.completions.parse(
            messages=messages, response_format=ConversationSummary
        )
        return response.choices[0].message.parsed
    except ValidationError as e:
        messages.append({"role": "user", "content": f"Fix these errors: {e}"})
raise LLMOutputError("Validation failed after 3 retries")
```

### 7. Pydantic V1 Patterns in V2 Codebase

```python
# ANTI-PATTERN (V1)
class MyModel(BaseModel):
    class Config:
        orm_mode = True

    @validator('field')
    def check(cls, v):
        return v

    obj.dict()
    Model.parse_obj(data)

# FIX (V2)
class MyModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    @field_validator('field')
    @classmethod
    def check(cls, v):
        return v

    obj.model_dump()
    Model.model_validate(data)
```

### 8. Sequential Independent Awaits

```python
# ANTI-PATTERN: 3x latency for independent operations
user = await fetch_user(id)
coach = await fetch_coach(id)
session = await fetch_session(id)

# FIX: Parallel execution (1x latency)
user, coach, session = await asyncio.gather(
    fetch_user(id),
    fetch_coach(id),
    fetch_session(id)
)
```

### 9. Missing Cleanup on Stream Disconnect

```python
# ANTI-PATTERN: Resources leak if client disconnects
async def stream_response():
    llm_client = create_client()
    async for chunk in llm_client.stream():
        yield chunk
    # If client disconnects, cleanup never runs

# FIX: Use try/finally
async def stream_response():
    llm_client = create_client()
    try:
        async for chunk in llm_client.stream():
            yield chunk
    finally:
        await llm_client.close()  # Always runs, even on disconnect
```

### 10. Unvalidated Tool Arguments from LLM

```python
# ANTI-PATTERN: LLM controls function arguments
func_args = json.loads(tool_call.function.arguments)
await function(**func_args)  # Arbitrary kwargs!

# FIX: Validate against schema
from pydantic import BaseModel

class CreateCoachArgs(BaseModel):
    coachName: str
    coachDescription: str

func_args = CreateCoachArgs.model_validate_json(tool_call.function.arguments)
await function(**func_args.model_dump())
```

---

## Performance Quick Reference

| Pattern | Cost | Fix |
|---------|------|-----|
| `time.sleep(n)` in async | Blocks entire event loop | `await asyncio.sleep(n)` |
| `response += chunk` in loop | O(n^2) memory | `list.append()` + `"".join()` |
| `await file.read()` | Full file in RAM | `while chunk := await file.read(1MB)` |
| `for key: await redis.get(key)` | N round-trips | Pipeline: 1 round-trip |
| `Model(**json.loads(raw))` | Extra dict allocation | `Model.model_validate_json(raw)` |
| `asyncio.create_task(x)` bare | Task GC'd in 3.12 | Save ref + done_callback |
| Full history to LLM | Token explosion | deque(maxlen=20) or token budget |
| `json.loads(llm.content)` | No validation | `response_format=PydanticModel` |
| No `max_tokens` on LLM call | Unbounded generation | Always set `max_tokens` |
| No semaphore on LLM calls | Provider rate limit hit | `asyncio.Semaphore(10)` |
