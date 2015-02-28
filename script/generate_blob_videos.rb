#!/usr/bin/ruby
require 'rubygems'
require 'active_support'
require 'parallel'

require 'optparse'
opt = OptionParser.new

@threads = Parallel.processor_count
opt.on('-t val','--threads val') {|v| @threads = v.to_i }
raise "ERROR: threads must be more than 0" if @threads < 1

opt.parse!(ARGV)

WIN = true
DEBUG = false
GPU_DEV = 0
if WIN then
	def conv2winPath(path)
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
	#puts "Parallel Exe. CPU count => #{Parallel.processor_count}"
  ts = {}
  ARGV.each{|arg|
    t = (@threads.to_f / ARGV.size)
    ts[arg] = t>0 ? t : 1
  }

	Parallel.each(ARGV, in_threads: @threads){|arg|
		IO.popen("ruby #{__FILE__} #{arg} -t #{ts[arg]}"){|io|
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
	has_temp_src = (src_mov == dest_mov)
	if has_temp_src then
		ext_name = File.extname(dest_mov)
		_dest_mov = File.dirname(dest_mov)+ "/" + File.basename(dest_mov,ext_name) + "_temp" + ext_name
	end

	if WIN then
		src_mov = conv2winPath(src_mov)
		_dest_mov_lin = _dest_mov
		_dest_mov = conv2winPath(_dest_mov)
	end

	command = "ffmpeg -y -hwaccel_device #{GPU_DEV} -hwaccel auto  -i \"#{src_mov}\" -vf trim=start_frame=#{start_frame}:end_frame=#{end_frame},setpts=PTS-STARTPTS -c:v libvpx -an \"#{_dest_mov}\" > /dev/null 2> /dev/null"
	#puts command
	puts "TRIM: #{File.basename(src_mov)} => #{File.basename(_dest_mov)} [#{start_frame} to #{end_frame}]"
	if DEBUG then
    `touch #{_dest_mov}`
  else
    `#{command}`
  end

	if has_temp_src then
		ext_name = File.extname(dest_mov)
		_dest_mov = File.dirname(dest_mov)+ "/" + File.basename(dest_mov,ext_name) + "_temp" + ext_name

		command = "mv \"#{_dest_mov}\" \"#{dest_mov}\""
		puts command
		`#{command}`
	end
end

def binary_trim(segments,s_off_set,src_mov,cam,cam_output_dir,end_frame,para)
	return if segments.size <= 1
	mid = (segments.size()/2).to_i
	dest_mov1 = "#{cam_output_dir}/#{"%07d"%(s_off_set+mid)}.webm"
	first_frame = @timestamps[cam].search_video_index(segments[0][:observ_frame])
	mid_frame = @timestamps[cam].search_video_index(segments[mid][:observ_frame])

  return unless first_frame
  return unless mid_frame
  if first_frame > end_frame or first_frame > mid_frame then
  	raise "ERROR: segments: [#{segments.join(", ")}]"
  end
  return if first_frame == end_frame

  do_trim = [(mid_frame-1 > first_frame), (end_frame-1 > mid_frame)]

	puts "Binary Trim(#{cam}): [#{first_frame}...#{end_frame}] -> [#{first_frame}..#{mid_frame-1}] + [#{mid_frame}..#{end_frame-1}]"
	trim(mid_frame-first_frame,end_frame-first_frame,src_mov,dest_mov1) if do_trim[1]

	dest_mov2 = "#{cam_output_dir}/#{"%07d"%(s_off_set)}.webm"
  if do_trim[0] then
  	trim(0,mid_frame-first_frame-1,src_mov,dest_mov2) if do_trim[0]
  else
    # フレーム数が0になるなら単純に消去してしまう．
    `rm -f dest_mov2`
  end

  para = para * 2

  if para <= [1,@threads/CAMERAS.size].max then
    args = []
    args << [segments[0..mid-1],s_off_set    ,dest_mov2,cam,cam_output_dir,mid_frame,para,do_trim[0]]
    args << [segments[mid..-1],s_off_set+mid,dest_mov1,cam,cam_output_dir,end_frame,para,do_trim[1]]
    Parallel.each(args,in_threads:2){|arg|
      binary_trim(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6]) if arg[7]
    }
  else
    # 完了の確認がしやすいように後半を先にやる
    binary_trim(segments[mid..-1],s_off_set+mid,dest_mov1,cam,cam_output_dir,end_frame,para) if do_trim[1]
    binary_trim(segments[0..mid-1],s_off_set    ,dest_mov2,cam,cam_output_dir,mid_frame,para) if do_trim[0]
  end
end

Parallel.each(CAMERAS, in_threads: Parallel.processor_count){|cam|
#CAMERAS.each{|cam|
	#next if cam != "cameraC"
	cam_file = data_id_dir + "/#{cam}_#{data_id}.mp4"
	cam_output_dir = "#{output_dir}/#{cam}"

	#####
	#segments = segments[0..10]
	binary_trim(segments,0,cam_file,cam,cam_output_dir,@timestamps[cam][-1][:observ_frame],1)
}


exit 0