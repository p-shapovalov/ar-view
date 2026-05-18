#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ar.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ar'
  s.version          = '0.0.1'
  s.summary          = 'AR view plugin for Flutter (ARKit + SceneKit + GLTFKit2).'
  s.description      = <<-DESC
Native AR plugin: renders glb models in an ARSCNView, anchored to vertical
planes. Loads glb via GLTFKit2 (SPM-only upstream, vendored here as a
prebuilt xcframework — see prepare_command).
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'

  # ARSCNView is iOS 11+; ARCoachingOverlayView (built-in "searching for
  # surfaces" UI) needs iOS 13+; the IosARView class is gated on iOS 13.
  s.platform = :ios, '13.0'

  # GLTFKit2 is SPM-only upstream (not on CocoaPods Trunk). The maintainer
  # publishes a prebuilt xcframework on each GitHub release, so we fetch
  # the matching version on `pod install` and reference it as a
  # vendored_framework. Frameworks/ is gitignored — first `pod install`
  # after a fresh clone pulls it (~36 MB).
  gltfkit2_version = '0.5.15'
  s.prepare_command = <<-CMD
    set -e
    if [ ! -d "Frameworks/GLTFKit2.xcframework" ]; then
      mkdir -p Frameworks
      curl -fsSL "https://github.com/warrenm/GLTFKit2/releases/download/#{gltfkit2_version}/GLTFKit2.xcframework.zip" -o /tmp/GLTFKit2-#{gltfkit2_version}.zip
      unzip -q /tmp/GLTFKit2-#{gltfkit2_version}.zip -d Frameworks/
      rm /tmp/GLTFKit2-#{gltfkit2_version}.zip
    fi
  CMD
  s.vendored_frameworks = 'Frameworks/GLTFKit2.xcframework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
