Gem::Specification.new do |spec|
  spec.name = 'ghostty_rails'
  spec.version = '0.1.0'
  spec.authors = ['Menlo Parking']
  spec.email = ['admin@menloparking.com']

  spec.summary =
    'Ghostty-powered terminal emulator for Rails'
  spec.description =
    'A Rails engine that provides a real ' \
    'terminal emulator in the browser using ' \
    'Ghostty WASM, ActionCable, and PTY. ' \
    'Supports local shell and SSH sessions ' \
    'with pluggable authorization and SSH ' \
    'identity resolution.'
  spec.homepage =
    'https://github.com/menloparking/ghostty_rails'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] =
    "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir[
    'lib/**/*',
    'app/**/*',
    'CHANGELOG.md',
    'LICENSE.txt',
    'README.md'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'actioncable', '>= 7.1'
  spec.add_dependency 'railties', '>= 7.1'
end
