class TaskPedesCount < MyTask
  def initialize(config={})
    @task = self.class.name.underscore
    super(@task)
    @@config = generate_config(config)
  end
  def view_path_check
    return "ERROR: This task (#{@task}) is not designed to double-check."#contents/#{@name}"
  end

  def load_timestamps(file)
    timestamps = []
    File.open(file).each{|line|
      line = line.strip
      next if line.empty?
      timestamps << parse_timestamp(line)
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
    all_data = Dir.glob(@@config[:data_path] + @@config[:glob_pattern]).delete_if{|v|
      !v.match(@@config[:data_id_regex])
    }.sort
    # task_pedes_countの生成
    count = 0

    for data_path in all_data do
      md = data_path.match(@@config[:data_id_regex])
      next unless md
      data_id = md[1]

      timestamps = load_timestamps("#{data_path}/#{@@config[:timestamp_file]}")
      blob_paths = Dir.glob("#{data_path}/**/*#{@@config[:image_extension]}").map{|v|v.gsub!(@@config[:data_path],'')}

      if timestamps.size != blob_paths.size then
        STDERR.puts "ERROR: number of frames and timestamps are not equal."
        next
      end

      i = 0
      for blob_path in blob_paths do

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
        ticket['timestamp'] = timestamps[i]
        ticket['frame'] = i
        ticket['frame_num'] = timestamps.size
        unless ticket.save! then
          raise MyCustomError, "新規チケットの発行に失敗しました"
        end
        i = i+1
      end
    end

    return count

  end

  def generate_meta_tags(ticket,current_task,user)
    meta_tags = {}
    meta_tags[:min_work_time] = @@util_funcs[:time2sec].call(@@config[:min_work_time]).to_s

    meta_tags[:image_width] = @@config[:image_width]
    meta_tags[:image_height] = @@config[:image_height]

    # 他の画像のタグを記録する
    meta_tags[:past_pedestrians] = {}
    tickets = Ticket.where(task:@task,blob_id:/#{ticket[:data_id]}.+/,completion:true)
    other_mtasks = MicroTask.where(task:@task,blob_id:/#{ticket[:data_id]}.+/)
    tickets.each{|t|
      completed_mtasks = other_mtasks.where(blob_id:t.blob_id)
      STDERR.puts "ERROR: empty completed_mtasks for blob_id:#{t.blob_id}"
      completed_mtask = completed_mtasks[0]
      next if completed_mtask['pedestrians'].empty?
      meta_tags[:past_pedestrians][t['blob_id']] = completed_mtask['pedestrians']
    }
    return MyTask::generate_meta_tags_base(meta_tags,ticket,current_task,user)
  end

  def parse_annotation(hash)
    annotation = {}
    return annotation unless hash[:pedestrians] and !hash[:pedestrians].empty?

    #画像のサイズで正規化しておく．
    array =  JSON.parse(hash[:pedestrians]).uniq
    for i in 0...array.length do
      array[i] = array[i].with_indifferent_access
      array[i][:x] = array[i][:x].to_f / @@config[:image_width]
      array[i][:width] = array[i][:width].to_f / @@config[:image_width]
      array[i][:y] = array[i][:y].to_f / @@config[:image_height]
      array[i][:height] = array[i][:height].to_f / @@config[:image_height]
      array[i][:gender]
      # 他にも属性があれば，ここに追加
    end
    annotation[:pedestrians] = array

    return annotation
  end


  def check_completion(ticket,mtasks)
    STDERR.puts "WARNING: This task is not designed to double-check the annotation."
    true
  end


end