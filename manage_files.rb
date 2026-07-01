require 'xcodeproj'

project_path = '/Users/tanqinghua/Personal/Notiee/Notiee.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Remove files
files_to_remove = [
  'WelcomeAndWhatsNewView.swift',
  'PermissionWizardView.swift'
]

project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXFileReference) && files_to_remove.include?(child.path)
    target.source_build_phase.remove_file_reference(child)
    child.remove_from_project
  end
end

# Add new files
files_to_add = [
  "Notiee/Features/Settings/WelcomeView.swift",
  "Notiee/Features/Settings/WhatsNewView.swift",
  "Notiee/Services/SystemPermissionManager.swift"
]

files_to_add.each do |file|
  parts = file.split('/')
  filename = parts.pop
  
  group = project.main_group
  parts.each do |dir|
    group = group.groups.find { |g| g.path == dir || g.name == dir || g.display_name == dir } || group.new_group(dir, dir)
  end
  
  file_ref = group.files.find { |f| f.path == filename }
  unless file_ref
    file_ref = group.new_file(filename)
    target.source_build_phase.add_file_reference(file_ref, true)
  end
end

project.save
puts "Files updated successfully."
