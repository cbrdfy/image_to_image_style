provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "services" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "artifactregistry.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    # Add this for Gen2 Cloud Function
    # Probably could be removed afterwards
    "eventarc.googleapis.com"
  ])
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Bucket for images (input/output)
resource "google_storage_bucket" "images" {
  name          = "${var.project_id}-image-style-app"
  location      = var.region
  force_destroy = true
}

# Bucket for Cloud Function ZIP
resource "google_storage_bucket" "function_bucket" {
  name          = "${var.project_id}-imagen-fn-src"
  location      = var.region
  force_destroy = true
}

resource "google_storage_bucket_object" "function_zip" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = "${path.module}/function-source.zip"
}

resource "google_service_account" "cloud_function_sa" {
  account_id   = "vertex-imagen-fn"
  display_name = "Cloud Function SA for Vertex API access"
}

resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

resource "google_cloudfunctions2_function" "style_image_fn" {
  name        = "style-image-gen-v2"
  location    = var.region
  description = "2nd Gen Cloud Function to call Vertex AI Imagen"

  build_config {
    runtime     = "python313"
    entry_point = "style_image_handler"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }

  service_config {
    available_memory      = "512M"
    timeout_seconds       = 60
    max_instance_count    = 3
    min_instance_count    = 0
    ingress_settings      = "ALLOW_ALL"
    service_account_email = google_service_account.cloud_function_sa.email
    environment_variables = {
      GCP_PROJECT   = var.project_id
      LOCATION      = var.region
      IMAGES_BUCKET = google_storage_bucket.images.name
    }
  }
}

data "google_iam_policy" "only_me" {
  binding {
    role    = "roles/cloudfunctions.invoker"
    members = ["user:my_email@gmail.com"]
  }
}

resource "google_cloudfunctions2_function_iam_policy" "lock_down" {
  location       = var.region
  cloud_function = google_cloudfunctions2_function.style_image_fn.name
  policy_data    = data.google_iam_policy.only_me.policy_data
}
