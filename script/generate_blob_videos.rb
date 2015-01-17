#!/usr/bin/ruby
require 'rubygems'
require 'active_support'
require 'parallel'

$stdout.sync = true

ARG_NUM = 1

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__} blob_images/DATA_ID"
	exit 1
end

if ARGV.size > ARG_NUM then
	puts "Parallel Exe. CPU count => #{Parallel.processor_count}"
	Parallel.each(ARGV, in_threads: Parallel.processor_count){|arg|
		IO.popen("ruby #{__FILE__} #{arg}"){|io|
			io.each{|line|
					puts line
			}
		}			
	}
	exit 1
end

data_id_dir = ARGV[0]



output_dir = data_id_dir + "/videos/"

CAMERAS = ['cameraA','cameraB','cameraC']

CAMERAS.each{|cam|
	`mkdir -p #{output_dir}/#{cam}`
}

data_id_10fps = []


data_id = File.basename(data_id_dir)

put_detection_delay = 30
put_detection_delay = 1 if data_id_10fps.include?(data_id)

def parseTimestamp(str)
	buf = /(\d{4}).(\d{2}).(\d{2})_(\d{2}).(\d{2}).(\d{2}).(\d+)/.match(str)
	return nil if nil == buf[0]
	Time.utc($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,"#{$6}.#{$7}".to_r)
end

timestamps = {}

CAMERAS.each{|cam|
	timestamp_file = "#{data_id_dir}/#{cam}_timestamp.csv"
	
	ts = []
	start_time = nil
	File.open(timestamp_file).each{|line|
		buf = line.split(",").map{|v|v.strip}
		next if buf[2].empty?
#=begin
		start_time = parseTimestamp(buf[2]) unless start_time		
		ts << {
			:observ_frame=>buf[1].to_i,
			:timestamp=>(parseTimestamp(buf[2]) - start_time)
		}
		#=end
#		ts << buf[1].to_i
	}
	timestamps[cam] = ts
}


# 切れ目
# putの方は少し早くしなければならない．
# 30fpsのものと10fpsのもので値が違う
segments = []
CAMERAS.each{|cam|
	ts = timestamps[cam]

	image_dir_put = "#{data_id_dir}/extract/#{cam}/PUT"
	Dir.glob("#{image_dir_put}/*.png").sort.each{|image|
		image =~ /putobject_(\d{7})_\d{3}\.png/
		frame = $1.to_i - put_detection_delay
		segments << ts[frame]	if ts[frame]

	}

	image_dir_taken = "#{data_id_dir}/extract/#{cam}/TAKEN"
	Dir.glob("#{image_dir_taken}/*.png").sort.each{|image|
		image =~ /takenobject_(\d{7})_\d{3}\.png/
		frame = $1.to_i
		segments << ts[frame]	if ts[frame]
	}
	
}
segments << {:observ_frame=>0,:timestamp=>0.0}

segments.sort_by!{|v|v[:observ_frame]}.uniq!

# output segments
fout = File.open("#{output_dir}/segments.csv",'w')
segments.each{|elem|
	fout.puts "#{elem[:observ_frame]}, #{elem[:timestamp]}"
}
fout.close

class Array
	def search_video_index(observ_frame)
		val = self.find{|v|v[:observ_frame]>=observ_frame}
		return nil unless val
		self.index(val)
	end
end

for i in 0...segments.size-1 do
	segment_obs = [segments[i][:observ_frame],segments[i+1][:observ_frame]]
	
	if segment_obs[0] > segment_obs[1] then
			STDERR.puts "Segments must be unique and sorted. This cannot happen."
			exit 0
	end
	
	#puts segment_obs.join(" => ")

	CAMERAS.each{|cam|
		cam_file = data_id_dir + "/#{cam}_#{data_id}.mp4"
		cam_output_dir = "#{output_dir}/#{cam}"
		start_frame = timestamps[cam].search_video_index(segment_obs[0])
		temp = timestamps[cam].search_video_index(segment_obs[1])
		next unless temp
		end_frame = temp -1
		end_frame = timestamps[cam][-1] unless end_frame # 
		next if start_frame >= end_frame
		
		output_file = "#{cam_output_dir}/#{"%07d"%i}.webm"
		next if File.exist?(output_file)
		command = "ffmpeg -ss 1 -i #{cam_file} -vf trim=start_frame=#{start_frame}:end_frame=#{end_frame},setpts=PTS-STARTPTS -an #{output_file}"
		puts command
		`#{command}`
	}
end



exit 0