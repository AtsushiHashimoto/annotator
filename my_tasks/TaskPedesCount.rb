class Task2 < MyTask
  def initialize(config={})
    @task = self.class.name.underscore
    super(@task)
    @@config = generate_config(config)
  end

  def load_timestamps(file)
    timestamps = []
    File.open(file).each{|line|
      line = line.strip
      next if line.empty?
      timestamps << parse_timestamps(line)
    }
    return timestamps
  end
  def parse_timestamp(str)
    STDERR.puts "WARNING: function 'parse_timestamp' is not implemented!"
    Time.now
  end

  # data_pathディレクトリ以下の構造
=begin
blob_images
┗cam125_line01
┗cam127_line01
┗cam141_line01
　┗line.png
　┗20140907
　　…
　┗20140920
　　┗timestamp.dat
　　┗10
　　　…
　　┗22
　　　┗00
　　　　…
　　　┗59
　　　　┗012345.png
　　　　　…
　　　　┗567890.png
=end
  def generate_tickets
    all_data = Dir.glob(@@config[:data_path] + @@config[:glob_pattern]).sort
    # task_pedes_countの生成
    count = 0

    for data_path in all_data do
      md = data_path.match(@@config[:data_id_regex])
      next unless md
      data_id = md[1]

      timestamps = load_timestamps
      blob_paths = Dir.glob("#{data_path}/**#{@@config[:image_extension]}")

      if timestamps.size != blob_paths then
        STDERR.puts "ERROR: number of frames and timestamps are not equal."
        next
      end

      i = 0
      for blob_path in blob_paths do
        timestamp = timestamps[i]
        i = i+1

        md = blob_path.match(@@config[:blob_id_regex])
        unless md then
          STDERR.puts "ERROR: invalid format image '#{blob_path}' (matching pattern: /#{@@config[:blob_id_regex]}/)"
          next
        end
        blob_id = md[1]

        # 既に登録があれば再生成や上書きはしない
        _id = "#{@task}_#{blob_id}"
        next if Ticket.duplicate?(_id)
        count = count + 1

        blob_path.gsub(@@config[:data_path],'')
        ticket = Ticket.new(_id: _id, blob_id: blob_id, task: @task, blob_path: blob_path, annotator:[])
        ticket['data_id'] = data_id
        unless ticket.save! then
          raise MyCustomError, "新規チケットの発行に失敗しました"
        end
      end
    end

    return count

  end
  def load_nlp_result_csv(dir)
    files = Dir.glob("#{dir}/*.csv")
    candidates = Hash.new{|h,k| h[k] = []}
    for file in files do
      buf = File.open(file,'r').read.toutf8
      words = buf.split("\n").map{|v|v.split(",")}.delete_if{|v|v.size < 4}
      words.map!{|v|v[3].strip}
      for key,array in @@config[:synonyms] do
        for word in words do
          next unless array.include?(word)
          candidates[key] << word
        end
        candidates[key].uniq!
      end
    end
    candidates
  end

  def generate_meta_tags(ticket,current_task,user)
    meta_tags = {}
    meta_tags[:min_work_time] = @@util_funcs[:time2sec].call(@@config[:min_work_time]).to_s

    synonyms = @@config[:synonyms]

    meta_tags[:list_ingredient] = synonyms[:ingredient].to_json
    meta_tags[:list_utensil   ] = synonyms[:utensil   ].to_json
    meta_tags[:list_seasoning ] = synonyms[:seasoning ].to_json
    meta_tags[:overview] = ticket[:blob_path] + "/" + @@config[:overview]

    return MyTask::generate_meta_tags_base(meta_tags,ticket,current_task,user)
  end
  def parse_annotation(hash)
    annotation = {}
    targets = [:ingredients,:utensils,:seasonings]
    for tar in targets do
      unless hash.include?(tar.to_s) then
        raise 500, "空の入力欄(#{tar})があります"
      end
      annotation[tar] = hash[tar].split(",")
    end
    return annotation
  end

  def view_path_check
    return "contents/#{@name}"
  end


end