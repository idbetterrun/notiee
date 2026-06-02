require 'xcodeproj'

project_path = '/Users/tanqinghua/Personal/Notiee/Notiee.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

files = [
  "Notiee/Features/Settings/PrivacyAgreementView.swift",
  "Notiee/Features/Settings/WelcomeView.swift",
  "Notiee/Features/Settings/WhatsNewView.swift",
  "Notiee/Features/Records/HighlightedText.swift",
  "Notiee/Features/Settings/BackupRestoreView.swift",
  "Notiee/Features/Settings/AboutNotieeView.swift",
  "Notiee/Features/Capture/NotieeCameraIntent.swift",
  "Notiee/Models/ScenePreset.swift",
  "Notiee/Services/LocalOCRService.swift",
  "Notiee/Services/NotieeStore+Actions.swift",
  "Notiee/Services/NotieeStore+Pipeline.swift",
  "Notiee/Components/FeatureHintView.swift",
  "Notiee/Services/NotificationManager.swift",
  "Notiee/Utils/Logger.swift",
  "Notiee/Utils/NotieeColors.swift"
]

files.each do |file|
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
puts "Files added successfully."
