require 'xcodeproj'

project_path = '/Users/tanqinghua/Personal/Notiee/Notiee.xcodeproj'
project = Xcodeproj::Project.open(project_path)

pkg_ref = project.root_object.package_references.find { |p| p.repositoryURL == "https://github.com/danielsaidi/OnboardingKit.git" }
if pkg_ref
  pkg_ref.requirement = {
    "kind" => "branch",
    "branch" => "main"
  }
end

project.save
puts "Fixed branch name to main."
