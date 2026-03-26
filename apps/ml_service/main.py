"""
Lincoln ML Service - Embedding generation for learning agents.

This service provides:
- Text embedding generation using sentence-transformers
- Batch embedding for efficiency
- Semantic similarity computation
"""

import logging
from contextlib import asynccontextmanager
from typing import List

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sentence_transformers import SentenceTransformer

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global model instance
model: SentenceTransformer | None = None
MODEL_NAME = "all-MiniLM-L6-v2"  # 384 dimensions, fast, good quality


class EmbedRequest(BaseModel):
    """Request for single text embedding."""

    text: str = Field(..., min_length=1, max_length=10000)


class EmbedBatchRequest(BaseModel):
    """Request for batch text embedding."""

    texts: List[str] = Field(..., min_length=1, max_length=100)


class SimilarityRequest(BaseModel):
    """Request for computing similarity between two texts."""

    text1: str = Field(..., min_length=1)
    text2: str = Field(..., min_length=1)


class EmbedResponse(BaseModel):
    """Response containing a single embedding."""

    embedding: List[float]
    dimensions: int


class EmbedBatchResponse(BaseModel):
    """Response containing multiple embeddings."""

    embeddings: List[List[float]]
    dimensions: int
    count: int


class SimilarityResponse(BaseModel):
    """Response containing similarity score."""

    similarity: float


class HealthResponse(BaseModel):
    """Health check response."""

    status: str
    model: str
    dimensions: int


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup, cleanup on shutdown."""
    global model
    logger.info(f"Loading model: {MODEL_NAME}")
    model = SentenceTransformer(MODEL_NAME)
    logger.info(f"Model loaded. Embedding dimensions: {model.get_sentence_embedding_dimension()}")
    yield
    model = None
    logger.info("Model unloaded")


app = FastAPI(
    title="Lincoln ML Service",
    description="Embedding generation service for Lincoln learning agents",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Check service health and model status."""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    return HealthResponse(
        status="healthy",
        model=MODEL_NAME,
        dimensions=model.get_sentence_embedding_dimension(),
    )


@app.post("/embed", response_model=EmbedResponse)
async def embed_text(request: EmbedRequest):
    """Generate embedding for a single text."""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        embedding = model.encode(request.text, convert_to_numpy=True)
        embedding_list = embedding.tolist()

        return EmbedResponse(
            embedding=embedding_list,
            dimensions=len(embedding_list),
        )
    except Exception as e:
        logger.error(f"Embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/embed/batch", response_model=EmbedBatchResponse)
async def embed_batch(request: EmbedBatchRequest):
    """Generate embeddings for multiple texts."""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        embeddings = model.encode(request.texts, convert_to_numpy=True)
        embeddings_list = embeddings.tolist()

        return EmbedBatchResponse(
            embeddings=embeddings_list,
            dimensions=len(embeddings_list[0]) if embeddings_list else 0,
            count=len(embeddings_list),
        )
    except Exception as e:
        logger.error(f"Batch embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/similarity", response_model=SimilarityResponse)
async def compute_similarity(request: SimilarityRequest):
    """Compute cosine similarity between two texts."""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        embeddings = model.encode([request.text1, request.text2], convert_to_numpy=True)
        similarity = float(
            np.dot(embeddings[0], embeddings[1])
            / (np.linalg.norm(embeddings[0]) * np.linalg.norm(embeddings[1]))
        )

        return SimilarityResponse(similarity=similarity)
    except Exception as e:
        logger.error(f"Similarity error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
