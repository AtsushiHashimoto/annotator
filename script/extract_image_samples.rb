#!/usr/bin/ruby
require 'rubygems'
require 'active_support'
require 'mongoid'
require 'yaml'
require 'parallel'
#require 'rmagick'

THIS_DIR = File.dirname(__FILE__)
IMG_EXT = '.png'
FAIL_EXT = '.fail'
TEMP_DIR = './temp'

ANNOTATE_ROOT = "../"

ARG_NUM = 2

if ARGV.size < ARG_NUM then
  STDERR.puts "USAGE: ruby #{__FILE__} annotator_url output_dir [environment]"
  exit 1
end

MIN_IMAGE_SIZE = 256

environment = :development
if ARGV.size > ARG_NUM
	environment = ARGV[ARG_NUM]
end

Mongoid.load!('./mongoid.yml', environment)

if environment == :development then
	YML_FILE = "#{THIS_DIR}/../config_dev.yml"
else
	YML_FILE = "#{THIS_DIR}/../config.yml"
end

conf = YAML.load_file(YML_FILE)


require "#{THIS_DIR}/../model_mongoid/ticket.rb"
require "#{THIS_DIR}/../model_mongoid/microtask.rb"



AnnotatorURL = ARGV[0]
OutputDir = ARGV[1]
ROI_FILE = "#{OutputDir}/roi.csv"

existing_images = Dir.glob("#{OutputDir}/**/*#{IMG_EXT}").map{|v|File.basename(v,IMG_EXT)}

synonym_file = conf['my_tasks']['task2']['synonym_file'].gsub("$ANNOTATE_ROOT",ANNOTATE_ROOT)
puts synonym_file
@synonims = {}
File.open(synonym_file,'r').each{|line|
	buf = line.split(/\s+/)
	if buf.size < 3 then
		STDERR.puts "ERROR unexpected format in '#{synonym_file}. A line must contain 3 blocks.'"
		STDERR.puts line
		exit
	end

	key = buf[-1]
	vals = buf[0...-1]
	vals[0] = vals[0].split('-')
	@synonims[key] = vals.flatten
}

# @synonims.each{|k,v|puts "#{k}: #{v.join(", ")}"}

def adjust_crop_area(x, width, im_width, min_width) # or y, height, im_height
  raise "ASSERT: #{width} <= min_width" if width > min_width
  if width < min_width then
    marjin = min_width - width
    if marjin%2==0 then
      lmarjin = marjin/2
    else
      lmarjin = (marjin/2).to_i+1
    end
    x = x - lmarjin
    x2 = x + min_width
    if x < 0 then
      x2 = x2 - x # あぶれた分を右へ
      x = 0
    end
    if x2 > im_width then
      x = x - (x2-im_width)
      x2 = im_width
    end
    raise "ASSERT im_width > min_width" if x<0
    width = x2-x
  end
  return x,width
end

# labelの表記揺れをsynonimsに従って補正(未実装)
def unify_spells(label)
	return label unless @synonims.include?(label)
	@synonims[label]
end

def add_group2file(file,group_name)
  unless File.exist?(file)
    fo = File.open(file,'w')
    fo.puts group_name
    fo.close
    return
  end
  groups = []
  File.open(file,'r').each{|line|
    groups << line.strip unless line.strip.empty?
  }
  return if groups.include?(group_name)

  fo = File.open(file,'a')
  fo.puts group_name
  fo.close
  return
end
group_file_name = "groups.dat"

sample_ids = []
Ticket.where(task:'task3',completion:true,blob_id:/PUT/).each{|t|
  sample_ids << t.blob_id
}

sample_ids.sort!

if File.exist?(ROI_FILE) then
  last_file = `tail -n 1 #{ROI_FILE}`.strip.split(",")[0]
  last_id = File.basename(last_file,'.png').gsub('..','::').gsub('.',':')
  puts last_file
  puts last_id
  puts sample_ids[0]
  index = sample_ids.index(last_id)
  sample_ids = sample_ids[index+1..-1]
end
`touch #{ROI_FILE}`
roi_fout = File.open(ROI_FILE,'a')


for sample_id in sample_ids do
  puts sample_id + " #{__LINE__}"

  mtask3 = MicroTask.where(task:'task3',blob_id:sample_id)[0]
  unless mtask3 then
    STDERR.puts "WARNING: no micro task for ticket #{sample_id}"
    next
  end
	label = mtask3['label'].strip
	bufs = label.split('::')
	bufs[0] = unify_spells(bufs[0])
	dir = "#{OutputDir}/#{bufs.flatten.join('/')}"
	`mkdir -p #{dir}`

  # サンプルのグループにレシピIDを追加
  data_id = sample_id.split(':')[0]
  add_group2file(dir+"/"+group_file_name, $1)  if data_id =~ /(\d{4}.+)_S\d+/

	output_base = sample_id.gsub('::','..').gsub(':','.')
	next if existing_images.include?(output_base)

  puts sample_id + " #{__LINE__}"


  output_file = "#{dir}/#{output_base}#{IMG_EXT}"
	next if File.exist?("#{output_file}#{FAIL_EXT}")

  puts sample_id + " #{__LINE__}"


  task1_blob_id,box_id = sample_id.split('::',2)
	mtask1 = MicroTask.where(task:'task1',blob_id:task1_blob_id)[0]
  next unless mtask1
  next unless mtask1['annotation']
	box = mtask1['annotation'][box_id.to_i]
  next unless box and box.include?('type')
	next unless box['type']=='put'

  puts sample_id + " #{__LINE__}"


  ticket1 = Ticket.where(task:'task1',blob_id:task1_blob_id)[0]
  image_url = "#{AnnotatorURL}/data_path/task1/#{ticket1['after_image']}"
	image_path = "#{TEMP_DIR}/#{File.basename(ticket1['after_image'])}"
  command = "wget #{image_url}"
  puts command
  `#{command}`
  `mv #{File.basename(ticket1['after_image'])} #{image_path}`

	unless File.exist?(image_path) then
		STDERR.puts "WARNING: image not found '#{image_path}'"
		next
	end
	#puts image_path

  im_width,im_height = `identify -format "%w %h" #{image_path}`.split(' ').map{|v|v.to_i}

  orig_x = im_width  * box['x']
  orig_y = im_height * box['y']
	orig_width = im_width * box['width']
  orig_height = im_height* box['height']
  min_width = [orig_width,orig_height,MIN_IMAGE_SIZE].max
  if min_width > im_width or min_width > im_height then
    STDERR.puts "too large object: #{sample_id}"
    next
    # でかすぎる物体は誤検出かなにかと思われるので，skip
  end

  x, width = adjust_crop_area(orig_x,orig_width,im_width,min_width)
  y, height = adjust_crop_area(orig_y,orig_height,im_height,min_width)

  `convert -crop #{width}x#{height}+#{x}+#{y} #{image_path} #{output_file}`
  `rm #{image_path}`
  roi_fout.puts [output_file, orig_x-x, orig_y-y, width, height].join(",")
=begin
  src_image = Magick::Image.read(image_path).first
  im_width = src_image.columns
  im_height= src_image.rows
  x = im_width * box['x']
  y = im_height * box['y']
  width = im_width * box['width']
  height = im_height * box['height']
  tar_image = src_image.crop(x, y, width, height)
  tar_image.write(output_file)
=end
end

roi_fout.close





exit 0