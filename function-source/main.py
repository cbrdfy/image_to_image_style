import base64
import os
import uuid
import time
import random
from flask import jsonify, Request
from google.cloud import aiplatform_v1, storage
from google.api_core.exceptions import GoogleAPIError
import functions_framework

PROJECT = os.environ["GCP_PROJECT"]
LOCATION = os.environ["LOCATION"]
IMAGES_BUCKET = os.environ["IMAGES_BUCKET"]

storage_client = storage.Client()
vertex_client = aiplatform_v1.PredictionServiceClient()

def upload_image_to_gcs(image_b64: str, file_name: str) -> str:
    bucket = storage_client.bucket(IMAGES_BUCKET)
    blob = bucket.blob(file_name)
    blob.upload_from_string(base64.b64decode(image_b64), content_type="image/png")
    return f"gs://{IMAGES_BUCKET}/{file_name}"

def call_vertex_with_retries(instance, endpoint, max_attempts=3):
    delay = 1
    for attempt in range(1, max_attempts + 1):
        try:
            return vertex_client.predict(endpoint=endpoint, instances=[instance])
        except GoogleAPIError as e:
            print(f"Retry on Vertex API error: {e}")
            if attempt == max_attempts:
                print(f"Vertex AI call failed after {max_attempts} attempts: {e}")
                raise e
            time.sleep(delay)
            delay *= random.uniform(1.5, 2.5)  # Exponential backoff

@functions_framework.http
def style_image_handler(request: Request):
    if request.method != "POST":
        return jsonify({"error": "Only POST method is supported"}), 405

    try:
        req_json = request.get_json()
        prompt = req_json["prompt"]
    except Exception as e:
        return jsonify({"error": f"Invalid JSON: {str(e)}"}), 400

    try:
        # Generate UUID to tag input/output
        image_id = str(uuid.uuid4())

        output_filename = f"output-{image_id}.png"

        # Call Vertex AI Imagen
        endpoint = f"projects/{PROJECT}/locations/{LOCATION}/publishers/google/models/imagegeneration"
        instance = {
            "prompt": prompt
        }

        response = call_vertex_with_retries(instance, endpoint)
        output_b64 = response.predictions[0]["bytesBase64Encoded"]

        # Save output image to GCS
        output_uri = upload_image_to_gcs(output_b64, output_filename)

        return jsonify({
            # "input_gcs_uri": input_uri,
            "output_gcs_uri": output_uri,
            "uuid": image_id
        })

    except Exception as e:
        return jsonify({"error": f"Processing failed: {str(e)}"}), 500
