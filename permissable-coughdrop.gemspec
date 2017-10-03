Gem::Specification.new do |s|
  s.name        = 'permissable-coughdrop'

  s.add_development_dependency 'rails'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'ruby-debug'

  s.version     = '0.3.1'
  s.date        = '2017-10-03'
  s.summary     = "Permissable"
  s.extra_rdoc_files = %W(LICENSE)
  s.homepage = %q{http://github.com/CoughDrop/permissable}
  s.description = "Permissions helper gem, used by multiple CoughDrop libraries"
  s.authors     = ["Brian Whitmer"]
  s.email       = 'brian.whitmer@gmail.com'

	s.files = Dir["{lib}/**/*"] + ["LICENSE", "README.md"]
  s.require_paths = %W(lib)

  s.license     = 'MIT'
end