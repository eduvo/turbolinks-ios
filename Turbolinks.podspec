Pod::Spec.new do |s|
  s.name         = "Turbolinks"
  s.version      = "3.1.0"
  s.summary      = "Turbolinks for iOS"
  s.homepage     = "http://github.com/turbolinks/turbolinks-ios"
  s.license      = "MIT"
  s.authors      = { "Sam Stephenson" => "sam@basecamp.com", "Jeffrey Hardy" => "jeff@basecamp.com", "Zach Waugh" => "zach@basecamp.com" }
  s.platform     = :ios, "8.0"
  s.source       = { :git => "git@github.com:eduvo/turbolinks-ios.git", :tag => "v3.1.0" }
  s.source_files = "Turbolinks/*.swift"
  s.resources    = "Turbolinks/*.js"
  s.framework    = "WebKit"
  s.swift_version = '5.0'
  s.requires_arc = true
end
