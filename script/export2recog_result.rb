#!/usr/bin/ruby

##########################################
# annotatorによるtask1, task3の結果を元に，
# 物体が取られたり置かれたりした時刻と，
# その物体の種類をファイルに書き出すプログラム
##########################################


require 'rubygems'
require 'json'
require 'csv'
require 'active_support'



# 認識対象の語彙集号
VOCABULARY = 'word.dat'

# blobの番号毎の認識結果
BLOB_CLASS = 'blob.csv'

# blobが検出された時刻
BLOB_DETECTION = 'blob_detection.csv'


# time stamp
TIME_STAMP_FILE = 'timestamp.csv'
# annotation data
TASK1_FILE = 'micro_tasks1.js'
TASK3_FILE = 'micro_tasks3.js'


if ARGV.size < 1 then
	# アノテーション結果は必ずannotator/blob_imagesの下にmicro_tasks?.jsという名前で置く．
	STDERR.puts "USAGE: ruby #{__FILE__} annotator/blob_images/DATA_ID/"
		exit 1
end

if ARGV[0][-1]!='/' then
	ARGV[0] = ARGV[0] + '/'
end

# DATA_PATHの下にはmicro_tasks{1,3}.js(mongo_dbのexport)と各カメラのtimestampが必要
DATA_PATH = ARGV[0]
DATA_ID = DATA_PATH.split('/')[-1]
mtasks1_file = DATA_PATH + TASK1_FILE
mtasks3_file = DATA_PATH + TASK3_FILE


# 出力目標
vocaburary = []
blob_class = {} # key: blobのID
blob_detection = {} #key: フレーム番号

def load_mongo_exported_js(file)
	data = []
	fin = File.open(file,'r')
	keys = fin.gets.strip.parse_csv
 	puts keys.join(' ')
	
	fin.each{|line|
			buf = line.strip.parse_csv
			
			if buf.size != keys.size then
					STDERR.puts "Unmatched length of keys and values" 
			end
			
			hash = {}
			for i in 0...keys.size do
					hash[keys[i]] = buf[i]
			end
			data << hash
	}
	fin.close
	data
end


# task1(領域指定)のパース
mtasks1 = load_mongo_exported_js(mtasks1_file)

# task3(物体名)のパース
mtasks3 = load_mongo_exported_js(mtasks3_file)

# 認識対象の語彙集合ファイルを作成する
for mtask in mtasks3 do
		label = mtask['label']
		next if vocaburary.include?(label)
		vocaburary << label
end
vocab_file = DATA_PATH + VOCABULARY
File.open(vocab_file,'w').puts vocaburary


class String
	def blob_id_parse(task)
			# "2014RC01_S020:extract:cameraA:PUT:putobject_0003012_016::1"
			buf = self.split(':')
			hash = {}
			hash[:recipe] = buf[0]
			hash[:camera] = buf[2]
			buf = buf[1..-1]
			case task
				when 'task1'
					temp,frame,blob_id =buf[-1].split('_')
					hash[:frame] = frame.to_i
					hash[:blob_id] = blob_id.to_i
					#	hash[:action] = buf[-2]
				when 'task3'
					hash[:box_id] = buf[-1].to_i
					
					temp,frame,blob_id =buf[-3].split('_')
					hash[:frame] = frame.to_i
					hash[:blob_id] = blob_id.to_i
			end
			hash
	end
end

# task1とtask2のアノテーションをリンクさせる
blobs = Hash.new{|hash,key|hash[key] = {}}
for mtask in mtasks1 do
	mtask.deep_merge!(mtask['blob_id'].blob_id_parse('task1'))
	blobs[mtask[:blob_id]][mtask[:frame]] = mtask
end

cameras = []
for mtask in mtasks3 do
	mtask.deep_merge!(mtask['blob_id'].blob_id_parse('task3'))
	i = mtask[:blob_id]
	j = mtask[:frame]
	boxes = JSON.parse(blobs[i][j]['annotation'])
	mtask[:box] = boxes[mtask[:box_id]]
	blobs[i][j][:micro_tasks3] = [] unless blobs[i][j].include?(:micro_tasks3)
	blobs[i][j][:micro_tasks3] << mtask
	cameras << mtask[:camera] unless cameras.include?(mtask[:camera])
end


def load_timestamp(file)
	buf = CSV.read(file)
	hash = {}
	for col in buf do
			hash[col[0].to_i] = col[2]
	end
	hash
end

# timestampを読み込む
timestamps = {}
for camera in cameras.sort do
	timestamp_file = "#{DATA_PATH}/#{camera}_#{TIMESTAMP_FILE}"
	timestamps[camera] = load_timestamp(timestamp_file)
end




# box毎の認識結果
blob_class_file = DATA_PATH + BLOB_CLASS

blob_class = {} # key: blobのID
buffer = []
for blob_id, temp in blobs do
		for frame, data in temp do
			next unless data[:micro_tasks3]
			for mtask3 in data[:micro_tasks3] do
				box_id = mtask3[:box_id]
				box = mtask3[:box]
				timestamp = timestamps[mtask3[:camera]][frame]
				buffer << "#{blob_id}_#{box_id}, #{box['type']}, #{timestamp}, #{mtask3['label']}:1.0"
			end
		end
end

buffers = buffer.sort_by{|v|
	v.split(',')[2].strip
}

fout = File.open(blob_class_file,'w')
for buf in buffers
		fout.puts buf
end
fout.close




