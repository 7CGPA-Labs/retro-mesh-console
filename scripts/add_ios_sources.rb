require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
group = project.main_group.find_subpath('Runner', true)

files_to_add = [
  'NetworkManager.swift',
  'CastingAdapter.swift',
  'WebCaster.swift',
  'native-render.mm',
  'native-audio.mm'
]

files_to_add.each do |file_name|
  file_path = "ios/Runner/#{file_name}"
  
  unless group.find_file_by_path(file_name)
    file_ref = group.new_reference(file_name)
    target.source_build_phase.add_file_reference(file_ref, true)
    puts "Added #{file_name} to project and Compile Sources phase."
  else
    puts "#{file_name} is already in the project."
  end
end

project.save
puts "Successfully updated project.pbxproj"
