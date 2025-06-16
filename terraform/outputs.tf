output "cloud_function_url" {
  description = "The HTTPS trigger URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.style_image_fn.service_config[0].uri
}
