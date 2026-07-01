require 'xcodeproj'

project_path = '/Users/tanqinghua/Personal/Notiee/Notiee.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Update Deployment Target
project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
end

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
  end
end

def add_spm_dependency(project, target_name, repo_url, product_name, branch_name)
  target = project.targets.find { |t| t.name == target_name }
  return unless target

  # Add package reference
  pkg_ref = project.root_object.package_references.find { |p| p.repositoryURL == repo_url }
  unless pkg_ref
    pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    pkg_ref.repositoryURL = repo_url
    pkg_ref.requirement = {
      "kind" => "branch",
      "branch" => branch_name
    }
    project.root_object.package_references << pkg_ref
  end

  # Add package product dependency
  pkg_product = target.package_product_dependencies.find { |p| p.product_name == product_name }
  unless pkg_product
    pkg_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    pkg_product.product_name = product_name
    pkg_product.package = pkg_ref
    target.package_product_dependencies << pkg_product
  end
end

add_spm_dependency(project, 'Notiee', 'https://github.com/danielsaidi/OnboardingKit.git', 'OnboardingKit', 'master')
add_spm_dependency(project, 'Notiee', 'https://github.com/SvenTiigi/WhatsNewKit.git', 'WhatsNewKit', 'main')

project.save
puts "Deployment target updated and SPM packages added."
