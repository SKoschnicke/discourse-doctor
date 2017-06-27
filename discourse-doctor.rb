#!/usr/bin/env ruby

Dir.chdir("/")
require 'bundler/inline'
require 'net/smtp'
require 'open-uri'
gemfile(true) do
  source 'https://rubygems.org'
  gem 'dnsruby'
  gem 'paint'
end
Dir.chdir("/var/www/discourse")

def log(level, message)
  $stderr.puts("#{level} #{message}")
end

def warning(message)
  log(Paint['warning', :yellow], message)
end

def error(message, log = nil)
  log(Paint['error', :red], message)
  exit(1)
end

def info(message)
  log(Paint['info', :green], message)
end

def check_env_var(var)
  if ENV[var].nil? || ENV[var].empty?
    error("#{var} is blank, edit containers/app.yml variables")
  end
end

def check_smtp_config
  info("Check SMTP configuration...")

  check_env_var("DISCOURSE_SMTP_ADDRESS")
  check_env_var("DISCOURSE_SMTP_PORT")
  check_env_var("DISCOURSE_SMTP_USER_NAME")
  check_env_var("DISCOURSE_SMTP_PASSWORD")

  begin
    Net::SMTP.start(ENV["DISCOURSE_SMTP_ADDRESS"], ENV["DISCOURSE_SMTP_PORT"])
             .auth_login(ENV["DISCOURSE_SMTP_USER_NAME"], ENV["DISCOURSE_SMTP_PASSWORD"])
  rescue Exception => e
    error("Couldn’t connect to SMTP server: #{e}")
  end
end

def grep_logs
  info("Search logs for errors...")

  system("grep -E \"error|warning\" /var/www/discourse/log/production.log | sort | uniq -c | sort -r")
end

def check_hostname
  info("Perform checks on the hostname...")

  check_env_var("DISCOURSE_HOSTNAME")

  begin
    resolver = Dnsruby::Resolver.new
    request = resolver.query(ENV["DISCOURSE_HOSTNAME"], Dnsruby::Types.TXT)
    answers = request.answer.map(&:to_s)

    if answers.select { |a| a.include?("spf") }.empty?
      warning("Please check SPF is correctly configured on this domain")
    end

    if answers.select { |a| a.include?("dkim") }.empty?
      warning("Please check DKIM is correctly configured on this domain")
    end
  rescue Dnsruby::NXDomain => e
    error("Non-existent Internet Domain Names Definition (NXDOMAIN) for: #{ENV["DISCOURSE_HOSTNAME"]}")
  end

  request = open("http://downforeveryoneorjustme.com/#{ENV["DISCOURSE_HOSTNAME"]}")
  unless request.status == ["200", "OK"]
    error("The internets can’t reach: #{ENV["DISCOURSE_HOSTNAME"]}")
  end
end

check_smtp_config
check_hostname
grep_logs