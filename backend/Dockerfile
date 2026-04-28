# ──────────────────────────────────────────────────
# Qurbani Hissah API — Hugging Face Spaces Dockerfile
# ──────────────────────────────────────────────────
# HF Spaces requires: port 7860, non-root user

FROM python:3.11-slim

# System deps for psycopg2-binary
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (HF Spaces requirement)
RUN useradd -m -u 1000 appuser

WORKDIR /app

# Install Python deps first (cache layer)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Switch to non-root user
USER appuser

# HF Spaces expects port 7860
EXPOSE 7860

# Start the server
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860"]
