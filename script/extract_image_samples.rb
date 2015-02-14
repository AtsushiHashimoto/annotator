#!/usr/bin/ruby
require 'rubygems'
require 'active_support'
require 'mongoid'
require 'yaml'
require 'rmagick'


THIS_DIR = File.dirname(__FILE__)
IMG_EXT = '.png'
FAIL_EXT = '.fail'

ARG_NUM = 1

if ARGV.size < ARG_NUM then
	STDERR.puts "USAGE: ruby #{__FILE__} output_dir"
	exit 1
end


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




OutputDir = ARGV[0]
existing_images = Dir.glob("#{OutputDir}/**/*#{IMG_EXT}").map{|v|File.basename(v,IMG_EXT)}


puts conf['task2']['synonims']
@synonims = {}
File.open(conf['task2']['synonims'],'r').each{|line|
	buf = line.split(/\s+/)
	if buf.size < 3 then
		STDERR.puts "ERROR unexpected format in '#{conf['task2']['synonims']}. A line must contain 3 blocks.'"
		STDERR.puts line
		exit
	end

	key = buf[-1]
	vals = buf[0...-1]
	vals[0] = vals[0].split('-')
	@synonims[key] = vals.flatten

}
# @synonims.each{|k,v|puts "#{k}: #{v.join(", ")}"}

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

Ticket.where(task:'task3',completion:true).each{|t|
	sample_id = t.blob_id
	mtask3 = MicroTask.where(task:'task3',blob_id:t.blob_id)[0]
	label = mtask3['label']
	bufs = label.split('::')
	bufs[0] = unify_spells(bufs[0])
	dir = "#{OutputDir}/#{bufs.flatten.join('/')}"
	`mkdir -p #{dir}`

  # サンプルのグループにレシピIDを追加
  data_id = t.blob_id.split(':')[0]
  add_group2file(dir+"/"+group_file_name, $1)  if data_id =~ /(\d{4}.+)_S\d+/

	output_base = sample_id.gsub('::','_').gsub(':','_')
	next if existing_images.include?(output_base)

	output_file = "#{dir}/#{output_base}#{IMG_EXT}"
	next if File.exist?("#{output_file}#{FAIL_EXT}")

	task1_blob_id,box_id = sample_id.split('::',2)
	mtask1 = MicroTask.where(task:'task1',blob_id:task1_blob_id)[0]
	box = mtask1['annotation'][box_id.to_i]

	next unless box['type']=='put'

	ticket1 = Ticket.where(task:'task1',blob_id:task1_blob_id)[0]
	image_path = "#{conf['image_blob_path']}/#{ticket1['after_image']}"

	unless File.exist?(image_path) then
		STDERR.puts "WARNING: image not found '#{image_path}'"
		next
	end
	#puts image_path

	src_image = Magick::Image.read(image_path).first
	im_width = src_image.columns
	im_height= src_image.rows
	x = im_width * box['x']
	y = im_height * box['y']
	width = im_width * box['width']
	height = im_height * box['height']
	tar_image = src_image.crop(x, y, width, height)
	tar_image.write(output_file)
}






exit 0