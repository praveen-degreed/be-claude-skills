# Codebase Patterns: Correct vs Wrong

Project-specific patterns for the Degreed Coach Builder. Agents MUST check these.

---

## 1. Logging

```python
# CORRECT
from app.log_manager import get_logger, log_info, log_error, log_warn, log_debug
log = get_logger(__name__)
log_info(log, "Processing query", session_id=sid)
log_error(log, "Failed to process", e=exc, session_id=sid)

# WRONG
print("Processing query")                    # Never use print
log.info("Processing query")                 # Missing session_id
logging.getLogger(__name__).info("...")      # Wrong import
log_error(log, "Failed", session_id=sid)     # Missing e= when exception available
```

## 2. Settings & Configuration

```python
# CORRECT
from app.core.settings import get_settings
settings = get_settings()
url = settings.AZURE_GPT_4O_ENDPOINT

# WRONG
url = os.environ.get("AZURE_GPT_4O_ENDPOINT")       # Use get_settings()
url = "https://hardcoded-endpoint.openai.azure.com"  # Never hardcode
API_KEY = "sk-..."                                   # Never hardcode secrets
```

New settings must:
- Be added to `settings.py` with proper type annotation
- Use `SecretStr` for sensitive values
- Have defaults or be documented in `.env.example`

## 3. DataDog Tracing

```python
# CORRECT
@tracer.wrap(name="dd_trace.my_feature", service="degreed-coach-builder", resource="maestro_experiences")
@router.post("/my-route/{session_id}")
async def my_endpoint(...):
    ...

# WRONG - missing tracer
@router.post("/my-route/{session_id}")
async def my_endpoint(...):
    ...

# WRONG - wrong service/resource
@tracer.wrap(name="my_feature")  # Missing service and resource

# WRONG - wrong decorator order
@router.post("/my-route/{session_id}")
@tracer.wrap(...)  # tracer MUST be BEFORE router decorator
async def my_endpoint(...):
```

After Pydantic parsing, always tag the trace:
```python
from app.services.observability.trace_tags import tag_from_request_model
tag_from_request_model(input_data, session_id=session_id)
```

## 4. Security Validation

```python
# CORRECT - every user-facing endpoint
security = SecurityValidation(sid, is_studio_endpoint=True, entity_type="coach")
await security.validate(
    user_profile_key=upk,
    coach_id=cid,
    conversation_id=conv_id,
    org_id=org_id
)

# WRONG - direct Redis access without auth
data = redis_manager.get_object(key=f"coach:{coach_id}")  # No auth check
```

Security exceptions (from `app/utils/security_exceptions.py`):
- `AuthenticationError` (401), `StudioAccessError` (403)
- `CoachAccessError`, `RoleplayAccessError`, `QuizAccessError` (403)
- `CoachError`, `ConversationError`, `RoleplayError` (404)

## 5. Redis Operations

```python
# CORRECT
from app.db.redis_manager import redis_manager
data = redis_manager.get_object(key=f"session:{sid}")
redis_manager.add_object(key=f"skill:{sid}", data=json.dumps(skill), expiry=86400)

# WRONG - direct client
import redis
r = redis.Redis()
r.get(key)

# WRONG - private method
redis_manager._get_client()

# WRONG - no TTL
redis_manager.add_object(key=f"data:{id}", data=json.dumps(d))  # No expiry!
```

For batch operations, use pipelines:
```python
# CORRECT
async with redis_client.pipeline() as pipe:
    for key in keys:
        pipe.get(key)
    results = await pipe.execute()

# WRONG - N+1
for key in keys:
    result = await redis_client.get(key)
```

## 6. LLM Structured Output

```python
# CORRECT - Pydantic model with response_format
from app.models.ai_structured_outputs import ConversationSummary

response = await client.beta.chat.completions.parse(
    model=get_azure_deployment_name(),
    messages=messages,
    response_format=ConversationSummary
)
result = response.choices[0].message.parsed

# WRONG - raw string parsing
response = await client.chat.completions.create(...)
result = json.loads(response.choices[0].message.content)  # No schema validation
```

New structured output models go in `app/models/ai_structured_outputs.py`.

## 7. Prompt Construction (Security)

```python
# CORRECT - structured roles with delimiters
messages = [
    {"role": "system", "content": system_prompt},
    {"role": "user", "content": f"<context>{sanitized_rag_content}</context>\n\n{user_query}"}
]

# WRONG - user input in system prompt
system = f"You are a coach. The user said: {raw_user_input}"

# WRONG - RAG in system without delimiter
system = f"{instructions}\n\nReference Material:\n{rag_content}"

# WRONG - no sanitization
messages = [{"role": "user", "content": raw_input}]
```

## 8. Async Patterns

```python
# CORRECT
await asyncio.sleep(1)

# WRONG - blocks event loop
time.sleep(1)

# CORRECT - parallel independent operations
a, b = await asyncio.gather(fetch_a(), fetch_b())

# WRONG - sequential when independent
a = await fetch_a()
b = await fetch_b()

# CORRECT - background tasks with strong reference
_bg_tasks = set()
task = asyncio.create_task(do_work())
_bg_tasks.add(task)
task.add_done_callback(_bg_tasks.discard)

# WRONG - fire and forget (Python 3.12 may GC the task)
asyncio.create_task(do_work())
```

## 9. Testing

```python
# CORRECT - use opt-in fixtures from conftest
def test_my_func(mock_redis_client):
    mock_redis_client.get.return_value = '{"key": "value"}'
    ...

# WRONG - re-mock auto-fixtures (already mocked!)
@patch('app.utils.llm_utils.get_embedding_model')  # Already auto-mocked!
def test_my_func(mock_embed):
    ...

# CORRECT - patch at import site
with patch('app.api.sse.redis_manager') as mock_rm:
    ...

# WRONG - patch at definition site
with patch('app.db.redis_manager.redis_manager') as mock_rm:
    ...

# CORRECT - async mock
mock_func = AsyncMock(return_value={"status": "ok"})

# WRONG - sync mock for async function
mock_func = MagicMock(return_value={"status": "ok"})
```

## 10. Error Handling

```python
# CORRECT
try:
    result = await external_call()
except SpecificError as e:
    log_error(log, "Context: what we were doing", e=e, session_id=sid)
    raise HTTPException(status_code=500, detail="User-safe message")

# WRONG - bare except, swallowed
try:
    result = await external_call()
except:
    pass

# WRONG - too broad, no logging
except Exception:
    return None

# WRONG - leaks internals
except Exception as e:
    raise HTTPException(status_code=500, detail=str(e))  # Stack trace to user!
```

## 11. Token Management

```python
# CORRECT - use existing utility
from app.utils.llm_utils import num_tokens_from_string
count = num_tokens_from_string(text, model_name)

# WRONG - reinventing
count = len(text.split())  # Inaccurate

# WRONG - reimplementing tiktoken
import tiktoken
enc = tiktoken.get_encoding("cl100k_base")
count = len(enc.encode(text))
```

## 12. Markdown Processing

```python
# CORRECT - use existing sanitizer
from app.utils.markdown_sanitizer import sanitize_markdown
clean = sanitize_markdown(llm_response, session_id)

# WRONG - manual cleanup
clean = llm_response.replace('\n\n\n', '\n\n')
```

## 13. File Processing

```python
# CORRECT - chunked reading
CHUNK_SIZE = 1024 * 1024  # 1MB
while chunk := await file.read(CHUNK_SIZE):
    process(chunk)

# WRONG - entire file in RAM
content = await file.read()  # Could be 500MB
```

## 14. Pydantic Models

```python
# CORRECT (V2 patterns)
from pydantic import BaseModel, Field, ConfigDict, field_validator

class MyModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, slots=True)
    my_field: str = Field(alias="MyField")

    @field_validator('my_field')
    @classmethod
    def validate_field(cls, v):
        ...

# WRONG (V1 patterns)
class MyModel(BaseModel):
    class Config:              # V1 style
        ...
    @validator('my_field')     # V1 decorator
    def validate_field(cls, v):
        ...
    .dict()                    # V1 method, use .model_dump()
    .parse_obj()               # V1 method, use .model_validate()
```

## 15. Request/Response Models

All request models inherit from `BaseSessionRequestModel` which provides:
- `populate_by_name=True` (supports both camelCase and PascalCase)
- `str_strip_whitespace=True`
- Common fields: userProfileKey, organizationId, conversationId, cookies, host

```python
# CORRECT - inherit from base
class MyRequest(BaseSessionRequestModel):
    my_field: str = Field(alias="MyField")

# WRONG - standalone model missing base fields
class MyRequest(BaseModel):
    my_field: str
```

## 16. Observability for Cross-Process Work

```python
# CORRECT - inject trace carrier for background/worker tasks
from app.services.observability.propagation import inject_trace_carrier, start_child_span_from_carrier

# Producer (FastAPI endpoint)
carrier = inject_trace_carrier()
redis_manager.add_object(key=f"trace:{id}", data=json.dumps(carrier))

# Consumer (daemon thread or LiveKit worker)
carrier_data = redis_manager.get_object(key=f"trace:{id}")
with start_child_span_from_carrier(json.loads(carrier_data), "operation_name"):
    await do_work()
```

## 17. Constants and Limits

Use existing constants from `app/utils/constants.py`:
- `CONTENT_FILTER_RESPONSE` - blocked content message
- `POST_PROCESS_TIMEOUT = 600`
- `FileStatus` - PROCESSING, SUCCESS, FAILED
- `ProcessingKeys` - 16+ event keys
- `CoachFieldLimits` - name(100), description(400), instructions(10000)

## 18. Concurrency Control for LLM Calls

```python
# CORRECT - bounded concurrency
LLM_SEMAPHORE = asyncio.Semaphore(10)

async def call_llm(messages):
    async with LLM_SEMAPHORE:
        return await client.chat.completions.create(messages=messages)

# WRONG - unbounded parallel calls
tasks = [call_llm(m) for m in all_messages]
results = await asyncio.gather(*tasks)  # Could overwhelm provider
```
