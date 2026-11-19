# Query only this app and build. Renew the short-lived ES256 JWT on each request.
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

def encode(data)
  Base64.urlsafe_encode64(data, padding: false)
end

def token
  key = OpenSSL::PKey.read(File.binread(ENV.fetch('ASC_KEY_PATH')))
  header = encode(JSON.generate(alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'))
  now = Time.now.to_i
  payload = encode(JSON.generate(iss: ENV.fetch('ASC_ISSUER_ID'), iat: now - 10, exp: now + 600,
                                 aud: 'appstoreconnect-v1'))
  message = "#{header}.#{payload}"
  der = key.sign('SHA256', message)
  raw = OpenSSL::ASN1.decode(der).value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
  "#{message}.#{encode(raw)}"
end

def query(path, params)
  uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
  uri.query = URI.encode_www_form(params)
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{token}"
  5.times do |attempt|
    begin
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
        http.request(request)
      end
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
      raise "Apple API #{response.code} (#{path})" unless [429, 500, 502, 503, 504].include?(response.code.to_i)
    rescue Timeout::Error, EOFError, Errno::ECONNRESET
      raise if attempt == 4
    end
    sleep(2 ** attempt)
  end
  abort "Apple API unavailable (#{path})"
end

bundle = 'org.handancampus.ios.native'
app = query('apps', 'filter[bundleId]' => bundle).fetch('data').first
abort "No visible App Store Connect record for #{bundle}" unless app
File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') do |f|
  f.puts "[TestFlight](https://appstoreconnect.apple.com/apps/#{app.fetch('id')}/testflight/ios)"
end
wait = ARGV.fetch(0) == 'wait'
deadline = Time.now + 40 * 60
loop do
  builds = query('builds', 'filter[app]' => app.fetch('id'), 'filter[version]' => ENV.fetch('TF_BUILD'),
                 'include' => 'preReleaseVersion')
  versions = (builds['included'] || []).select { |v| v.dig('attributes', 'version') == '0.1.0' }.map { |v| v['id'] }
  build = builds.fetch('data').find { |b| versions.include?(b.dig('relationships', 'preReleaseVersion', 'data', 'id')) }
  state = build&.dig('attributes', 'processingState')
  abort "Apple rejected build #{ENV.fetch('TF_BUILD')}: #{state}" if %w[FAILED INVALID].include?(state)
  unless wait
    File.open(ENV.fetch('GITHUB_OUTPUT'), 'a') { |f| f.puts "exists=#{!build.nil?}" }
    break
  end
  puts "Build #{ENV.fetch('TF_BUILD')}: #{state || 'awaiting Apple registration'}"
  if state == 'VALID'
    File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') { |f| f.puts "Apple processing: VALID, 0.1.0 (#{ENV.fetch('TF_BUILD')})." }
    break
  end
  abort 'Upload submitted; Apple processing has not finished within the polling window.' if Time.now >= deadline
  sleep 45
end
