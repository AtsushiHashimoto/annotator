#!/usr/bin/ruby

CAMERAS = ["cameraA","cameraB","cameraC"]

if ARGV.size < 2 then
	STDERR.puts "USAGE: #{__FILE__} src_dir tar_dir"
end

src_dir = ARGV[0]
tar_dir = ARGV[1]

data_ids = Dir.glob("#{src_dir}/2014*")
for dir in data_ids.sort do
	data_id = File.basename(dir)
	next unless data_id=~/2014RC01.*/
	for cam in CAMERAS do
		# skip if there are already data
		sdir = "#{dir}/#{cam}"
		next unless File.exist?(sdir)
		tdir = "#{tar_dir}/#{data_id}/#{cam}"
		next if File.exist?(tdir)
		command = "cp -r #{sdir} #{tdir}"
		puts command
		`#{command}`
		sdirs = Dir.glob("#{dir}/*/#{cam}")
		for sdir in sdirs
			sdir =~ /#{dir}\/(.+)\/#{cam}/
			tdir = "#{tar_dir}/#{data_id}/#{$1}/#{cam}"
			command = "cp -r #{sdir} #{tdir}"
			puts command
			`#{command}`
		end
	end
end
