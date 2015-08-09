class TaskPedesCount < MyTask
  def initialize(config={})
    @task = self.class.name.underscore
    super(@task)
    @@config = generate_config(config)
  end
  def view_path_check
    return "ERROR: This task (#{@task}) is not designed to double-check."#contents/#{@name}"
  end

  def load_timestamps(data_dir)
    timestamp_files = Dir.glob("#{data_dir}/#{@@config[:timestamp_files]}").sort

    timestamps = []
    puts timestamp_files
    for file in timestamp_files do
      File.open(file).each{|line|
        line = line.strip
        next if line.empty?
        timestamps << parse_timestamp(line)
      }
    end
    return timestamps
  end

  def parse_timestamp(str)
    # 2014.09.09_10.00.21.341.jpg
    md = str.match(/\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}\.\d{3}.*/)
    unless md then
      STDERR.puts "#{str} does not matched to the pattern."
    end
    return Time.local(md[1],md[2],md[3],md[4],md[5],md[6],md[7].to_i*1000)
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
  def get_cam_id(blob_id)
    puts blob_id
    md = blob_id.match(@@config[:cam_id_regex])
    return nil unless md
    puts md[1]
    md[1]
  end
  def get_data_id(blob_id)
    md = blob_id.match(@@config[:data_id_regex])
    return nil unless md
    data_id = md[1]
  end

  def generate_tickets
    all_data = Dir.glob(@@config[:data_path] + @@config[:glob_pattern]).delete_if{|v|
      !v.match(@@config[:data_id_regex])
    }.sort
    # task_pedes_countの生成
    count = 0

    for data_path in all_data do
      timestamps = load_timestamps(data_path)
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

    data_id = get_data_id(ticket[:blob_id])
    meta_tags[:data_id] = data_id
    cam_id = get_cam_id(ticket[:blob_id])
    meta_tags[:cam_id] = cam_id

    meta_tags[:line_imagepath] = "/data_path/#{@task}/#{cam_id}/#{@@config[:line_file]}"
    meta_tags[:src_imagepath] = "/data_path/#{@task}/#{ticket[:blob_path]}"
    tickets = Ticket.where(task:@task,blob_id:/#{data_id}.+/,completion:true)
    other_mtasks = MicroTask.where(task:@task,blob_id:/#{data_id}.+/)
=begin
    tickets.each{|t|
      completed_mtasks = other_mtasks.where(blob_id:t.blob_id)
      if completed_mtasks.count == 0 then
        STDERR.puts "ERROR: empty completed_mtasks for blob_id:#{t.blob_id}"
        next
      end

      completed_mtask = completed_mtasks[0]
      next if completed_mtask['pedestrians'].empty?
    }
=end
    return MyTask::generate_meta_tags_base(meta_tags,ticket,current_task,user)
  end

  def get_canvas_imagepath(blob_id)
    canvas_dir = "#{@@config[:data_path]}/canvas/#{get_data_id("/#{blob_id}")}"
    return "#{canvas_dir}/#{File.basename(blob_id,@@config[:image_extension])}.png"
  end

  # annotationにデータを入れて返す
  def parse_annotation(hash)
    annotation = {pedestrians:[]}
    return annotation if !hash.include?('rect') or hash[:rect].size < 1

    puts hash[:rect]
    if hash[:rect].class == String then
      # overwrite時にはsessionに格納されることで(?)何故かarrayが文字列になる
      hash[:gender] = JSON.parse(hash[:gender])
      hash[:direction] = JSON.parse(hash[:direction])
      hash[:rect] = JSON.parse(hash[:rect])
    end
    for i in 0...hash[:rect].size do
      annotation[:pedestrians] << {
          gender:hash[:gender][i],
          direction:hash[:direction][i],
          rect:JSON.parse(hash[:rect][i])
      }
      return nil if hash[:direction][i] == "not set"
    end

    canvas_imagepath = get_canvas_imagepath(hash[:blob_id])
    annotation[:canvas_imagepath] = "/data_path/#{@task}"+canvas_imagepath.gsub(@@config[:data_path],'')

    if hash.include?('canvas_data') then
      command = "mkdir -p #{File.dirname(canvas_imagepath)}"
      `#{command}`
      File.open(canvas_imagepath,"w").write(Base64.decode64(hash[:canvas_data]))
    else
      STERR.puts "neither canvas_data nor canvas_imagepath are found." unless hash.include?('canvas_imagepath')
      command = "mv #{hash[:canvas_imagepath]} #{annotation[:canvas_imagepath]}"
      `#{command}`
    end

    if hash.include?('jump') then
      if(my_id>hash[:jump]) then
        # 指定のフレーム（自分より前）だけタグを付け直す
      else
        # 自分のframe_idの次からjumpの前までの，タグ付けがまだなものを，人無し，とする．
      end
    end

    return annotation
  end

  def get_temp_imagepath(blob_id,user_name)
    temp_dir = "#{@@config[:data_path]}/temp/#{user_name}/#{get_data_id("/#{blob_id}")}"
    return "#{temp_dir}/#{File.basename(blob_id,@@config[:image_extension])}.png"
  end

  def overwrite_hook(hash,user_name)
    return hash unless hash.include?('canvas_data')
    temp_imagepath = get_temp_imagepath(hash[:blob_id],user_name)
    `mkdir -p #{File.dirname(temp_imagepath)}`
    File.open(temp_imagepath,"w").write(Base64.decode64(hash[:canvas_data]))
    hash.delete('canvas_data')
    hash[:canvas_imagepath] = temp_imagepath
    return hash
  end


  def refresh_ticket_pool
    hash = Hash.new{|hash,key| hash[key] = {}} # poolの元

    tickets = Ticket.where(task:@task,completion:false)
    pools = []
    return pools if tickets.count() == 0

    puts tickets.count()
    for t in tickets do
      key = get_data_id(t.blob_path)
      value = File.basename(t.blob_path)
      hash[key][value] = t
      puts "#{key}.#{value} = #{t._id}"
    end

    # key毎にvalueでsortしてpoolにする
    for key, val in hash do
      subtask = key.gsub(@task,"").gsub("/",":")

      puts "task: #{@task} subtask: #{subtask}"
      min_tasks = @config[:minimum_micro_task_num]

      # checkタスクと分ける
      #        puts "#{min_tasks} #{task} #{subtask}"
      pool = TicketPool.generate(:task,min_tasks,@task,subtask)
      pool_check = TicketPool.generate(:check,1,@task,subtask)
      #        puts "Users: #{pool.users}"
      #        puts "Users(check): #{pool_check.users}"

      for index, t in val.sort do
        if has_enough_microtasks(t,min_tasks) then
          #puts "check"
          #pool_check.tickets[index] = t._id
          STDERR.puts "#{@task} is not designed for double-check."
        else
          puts "task"
          pool.tickets[index] = t._id
        end
      end

      # ticketsの数が多かったら分割! (未実装)

      unless pool.tickets.empty? then
        STDERR.puts "failed to save a new pool." unless pool.save!
        pools << pool
      end
      unless pool_check.tickets.empty? then
        STDERR.puts "failed to save a new pool_check." unless pool_check.save!
        pools << pool_check
      end
    end
    return pools
  end

  def check_completion(ticket,mtasks)
    STDERR.puts "WARNING: This task is not designed to double-check the annotation."
    true
  end

  def get_frame_info(data_id,frame)
    ticket = Ticket.where(task:@task,blob_id:/#{data_id}/)#.*#{frame}#{@@config[:image_extension]}/)#.sort[frame.to_i]
    mtasks = MicroTask.where(task:@task,blob_id:ticket[frame]['blob_id'])

    image_path = "/data_path/#{@task}/#{ticket[frame]['blob_path']}"

    if mtasks.size < 1 then
      pedestrians = nil
    else
      mtask = mtasks[0]
      image_path = mtask['canvas_imagepath'] unless mtask['pedestrians'].empty?
      pedestrians = mtask['pedestrians']
    end

    return image_path, pedestrians
  end

  def rendering_frame(params={frame_id:0,data_id:""})
    params[:config] = @@config
    return "contents/task_pedes_count_rendering_frame"
  end

end
