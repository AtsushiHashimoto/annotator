#!/usr/bin/ruby
require 'rubygems'
require 'active_support'
require 'parallel'

WIN = false
GPU_DEV = 0
if WIN then
	def conv2winPath(path)
		puts path
		win_path = ""
		if path =~ /\/cygdrive\/(.)\/(.*)/ then
			win_path = "#{$1.upcase}:\\"
			path = $2
		end
		flag_not_file = false
		if path =~ /(.+)\/$/ then
			flag_not_file = true
			path = $1
		end
		win_path = win_path + path.split("/").join("\\")
		win_path = win_path + "\\" if flag_not_file

		return win_path
	end
else
	WIN_DRIVE = ""
end

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

@timestamps = {}

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
	@timestamps[cam] = ts
}




# 切れ目
# putの方は少し早くしなければならない．
# 30fpsのものと10fpsのもので値が違う
segments = []
CAMERAS.each{|cam|
	ts = @timestamps[cam]

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

def trim(start_frame,end_frame, src_mov, dest_mov)
	_dest_mov = dest_mov
	if src_mov == dest_mov then
		ext_name = File.extname(dest_mov)
		_dest_mov = File.dirname(dest_mov)+File.basename(dest_mov,ext_name) + "_temp" + ext_name
	end

	if WIN then
		src_mov = conv2winPath(src_mov)
		_dest_mov = conv2winPath(_dest_mov)
	end
	command = "ffmpeg -y -hwaccel_device #{GPU_DEV} -hwaccel auto  -i \"#{src_mov}\" -vf trim=start_frame=#{start_frame}:end_frame=#{end_frame},setpts=PTS-STARTPTS -c:v libvpx -an \"#{_dest_mov}\""
	puts command
	`#{command}`
	if src_mov == dest_mov then
		ext_name = File.extname(dest_mov)
		_dest_mov = File.dirname(dest_mov)+File.basename(dest_mov,ext_name) + "_temp" + ext_name
		`mv #{_dest_mov} #{dest_mov}`
	end
end


def binary_trim(segments,s_off_set,src_mov,cam,cam_output_dir,end_frame)
	return if segments.size == 1
	mid = (segments.size()/2).to_i
	dest_mov1 = "#{cam_output_dir}/#{"%07d"%(s_off_set+mid)}.webm"
	first_frame = @timestamps[cam].search_video_index(segments[0][:observ_frame])
	mid_frame = @timestamps[cam].search_video_index(segments[mid][:observ_frame])
	raise "ERROR: segments: [#{segments.join(", ")}]" if first_frame >= end_frame or first_frame >= mid_frame

	puts "binary_trim(#{cam}): [#{first_frame}...#{end_frame}] -> [#{first_frame}...#{mid_frame}] + [#{mid_frame}...#{end_frame}]"
	trim(mid_frame-first_frame,end_frame-first_frame,src_mov,dest_mov1)
	dest_mov2 = "#{cam_output_dir}/#{"%07d"%(s_off_set)}.webm"
	trim(0,mid_frame-1,src_mov,dest_mov2)
	binary_trim(segments[0...mid],s_off_set,    dest_mov2,cam,cam_output_dir,mid_frame-1)
	binary_trim(segments[mid..-1],s_off_set+mid,dest_mov1,cam,cam_output_dir,end_frame)
end


CAMERAS.each{|cam|
	next if cam != "cameraA"
	cam_file = data_id_dir + "/#{cam}_#{data_id}.mp4"
	cam_output_dir = "#{output_dir}/#{cam}"
	binary_trim(segments,0,cam_file,cam,cam_output_dir,@timestamps[cam][-1][:observ_frame])
}


exit 0