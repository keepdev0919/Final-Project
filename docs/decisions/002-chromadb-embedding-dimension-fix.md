# 002. ChromaDB 임베딩 차원 불일치 문제 해결

**날짜**: 2026-04-08  
**증상**: POST /course/recommend → 500 Internal Server Error

---

## 오류 메시지

```
chromadb.errors.InvalidArgumentError:
Collection expecting embedding with dimension of 1536, got 384
```

---

## 원인 분석

**인제스트 시점 (scripts/ingest_to_vector_db.py)**:
- OpenAI `text-embedding-3-small` (1536-dim)으로 벡터 생성
- `collection.add(embeddings=embeddings, ...)` → 벡터를 직접 삽입
- ChromaDB 컬렉션에 embedding function을 명시하지 않았기 때문에, 컬렉션 메타데이터에 "default" (로컬 ONNX, 384-dim)으로 기록됨

**쿼리 시점 (backend/services/db.py)**:
- `client.get_collection(COLLECTION_NAME)` — embedding function 미지정
- `collection.query(query_texts=[query])` 호출 시 ChromaDB가 "default" 로컬 모델(384-dim)로 쿼리 텍스트를 임베딩
- 저장된 벡터(1536-dim)와 차원 불일치 → 오류 발생

**시도했으나 실패한 방법**:
- `get_collection(COLLECTION_NAME, embedding_function=OpenAIEmbeddingFunction(...))`
- → "Embedding function conflict: new: openai vs persisted: default" 오류
- 컬렉션 메타데이터에 이미 "default"가 기록되어 있어 덮어쓸 수 없음

---

## 해결책

`query_texts` 대신 `query_embeddings`를 사용.  
쿼리 텍스트를 ChromaDB에 맡기지 않고 서버에서 직접 OpenAI API로 임베딩 후 전달.

```python
# backend/services/db.py 에 추가
def embed_query(text: str) -> list[float]:
    """OpenAI API로 텍스트를 1536-dim 벡터로 임베딩."""
    payload = json.dumps({"input": text, "model": "text-embedding-3-small"})
    # OpenAI /v1/embeddings 호출
    return body["data"][0]["embedding"]

# 사용처 (course_agent.py, routers/chat.py)
results = collection.query(
    query_embeddings=[embed_query(query)],  # query_texts 대신
    ...
)
```

---

## 수정 파일

- `backend/services/db.py`: `embed_query()` 함수 추가, `.env` 로딩 추가
- `backend/agents/course_agent.py`: `query_texts` → `query_embeddings`
- `backend/routers/chat.py`: `search_folklore`, `search_folktale` 동일하게 수정

---

## 교훈

ChromaDB에 벡터를 직접 삽입(`embeddings=` 파라미터)할 때는  
컬렉션 생성 시 반드시 embedding function을 명시해야 함.  
명시하지 않으면 쿼리 시 기본 로컬 모델이 사용되어 차원 불일치가 발생할 수 있음.
