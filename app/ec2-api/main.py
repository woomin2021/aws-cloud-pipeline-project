import os
import hashlib
import io
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import boto3
from botocore.exceptions import NoCredentialsError

app = FastAPI()

S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "self-test-bucket-123")
AWS_REGION = os.getenv("AWS_REGION", "ap-northeast-2")

s3_client = boto3.client('s3', region_name=AWS_REGION)

@app.get("/")
async def root():
    return {"message": "Hello, Yuna's API App is Running!"}

@app.post("/upload/")
async def upload_file(file: UploadFile = File(...)):
    filename = file.filename
    s3_key = f"uploads/{filename}"

    try:
        file_bytes = await file.read()

        # SHA-512 무결성 검증 (CPU 연산)
        hash_value = hashlib.sha512(file_bytes).hexdigest()

        s3_client.upload_fileobj(
            io.BytesIO(file_bytes),
            S3_BUCKET_NAME,
            s3_key,
            ExtraArgs={'ContentType': file.content_type}
        )

        return JSONResponse(content={
            "message": "File uploaded successfully!",
            "bucket": S3_BUCKET_NAME,
            "key": s3_key,
            "sha512": hash_value,
            "url": f"https://{S3_BUCKET_NAME}.s3.{AWS_REGION}.amazonaws.com/{s3_key}"
        }, status_code=200)

    except NoCredentialsError:
        raise HTTPException(status_code=403, detail="AWS credentials not found.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"An error occurred: {str(e)}")