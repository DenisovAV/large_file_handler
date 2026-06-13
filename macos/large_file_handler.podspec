#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint large_file_handler.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'large_file_handler'
  s.version          = '0.5.0'
  s.summary          = 'Copy large files from assets or download them from the network to local storage.'
  s.description      = <<-DESC
Efficiently copy large files from Flutter assets or download them from the network to the device's local file system, with optional progress tracking.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/large_file_handler'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sasha Denisov' => 'denisov.shureg@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
