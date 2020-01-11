# See https://github.com/ianheggie/health_check#configuration

HealthCheck.setup do |config|
  # uri prefix (no leading slash)
  config.uri = 'health-check'
end