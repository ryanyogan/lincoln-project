# Lincoln ML Service

Embedding generation service for Lincoln learning agents.

## Features

- Text embedding generation using sentence-transformers
- Batch embedding for efficiency
- Semantic similarity computation
- Uses `all-MiniLM-L6-v2` model (384 dimensions)

## Running Locally

### With Python

```bash
# Install dependencies
pip install -e .

# Run the service
python main.py
# or
uvicorn main:app --reload
```

### With Docker

```bash
docker build -t lincoln-ml-service .
docker run -p 8000:8000 lincoln-ml-service
```

## API Endpoints

### Health Check

```bash
curl http://localhost:8000/health
```

### Single Embedding

```bash
curl -X POST http://localhost:8000/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello, world!"}'
```

### Batch Embeddings

```bash
curl -X POST http://localhost:8000/embed/batch \
  -H "Content-Type: application/json" \
  -d '{"texts": ["Hello", "World", "How are you?"]}'
```

### Similarity

```bash
curl -X POST http://localhost:8000/similarity \
  -H "Content-Type: application/json" \
  -d '{"text1": "Hello world", "text2": "Hi there"}'
```

## Configuration

The service uses the `all-MiniLM-L6-v2` model by default, which provides:
- 384-dimensional embeddings
- Fast inference
- Good quality for semantic similarity
