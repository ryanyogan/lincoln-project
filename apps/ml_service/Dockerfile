# Lincoln ML Service - Embedding Generation
#
# Build: docker build -t lincoln-ml .
# Run:   docker run -p 8000:8000 lincoln-ml

FROM python:3.12-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install system dependencies (curl for healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
# Extract dependencies from pyproject.toml using pip
COPY pyproject.toml .

# Install dependencies directly with pip (faster than building a wheel)
RUN pip install \
    "fastapi>=0.109.0" \
    "uvicorn>=0.27.0" \
    "sentence-transformers>=2.3.0" \
    "numpy>=1.26.0" \
    "pydantic>=2.5.0"

# Copy application code
COPY main.py .

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    mkdir -p /home/appuser/.cache/huggingface && \
    chown -R appuser:appuser /app /home/appuser/.cache
USER appuser

# Set cache directory for model downloads
ENV HF_HOME=/home/appuser/.cache/huggingface \
    TRANSFORMERS_CACHE=/home/appuser/.cache/huggingface

# Pre-download the model during build (optional but faster startup)
# Uncomment to bake model into image (adds ~500MB to image size)
# RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the service
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
