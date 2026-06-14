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
  s.source_files = 'large_file_handler/Sources/large_file_handler/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'large_file_handler_privacy' => ['large_file_handler/Sources/large_file_handler/Resources/PrivacyInfo.xcprivacy']}
end
