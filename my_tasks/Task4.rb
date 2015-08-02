class Task4 < MyTask
  def initialize(config={})
    @task = self.class.name.underscore
    super(@task)
    @@config = generate_config(config)
  end

  def view_path_check
    return "contents/#{@name}"
  end

  def generate_tickets
    #puts @@config[:data_path] + @@config[:glob_pattern]
    all_datas = Dir.glob(@@config[:data_path] + @@config[:glob_pattern]).sort
    # task4の生成
    # videosディレクトリがあるデータをチェック
    count = 0
    for data_path in all_datas do
      md = data_path.match(@@config[:data_id_regex])
      next unless md
      data_id = md[1]#.gsub("/",":")
      video_list = Dir.glob("#{data_path}/*/*#{@@config[:video_extension]}").map{|v|
          File.basename(v.strip,@@config[:video_extension])
      }.sort

      # segmentの情報を読み込む
      segment_file = data_path + '/' + @@config[:segment_file]
      segments = []
      File.open(segment_file,'r').each{|line|
        frame,time = line.split(',').map{|v|v.strip}
        segments << {:frame=>frame.to_i, :time=>time.to_f}
      }

      for i_str in video_list[0...-1] do
        i = i_str.to_i

        blob_id = "#{data_id}:video:#{i_str}"
        t_id = @task + ':' + blob_id

        next unless Ticket::where(_id:t_id).empty?

        blob_path = "#{data_id}/#{@@config[:video_dir]}/#{i_str}#{@@config[:video_extension]}"

        ticket = Ticket.new(_id: t_id, blob_id: blob_id, task: @task, blob_path: blob_path, annotator:[])

        ticket['start_frame'] = segments[i][:frame]
        ticket['start_time'] = segments[i][:time]
        next if i+1 == segments.size
        ticket['end_frame'] = segments[i+1][:frame]
        ticket['end_time'] = segments[i+1][:time]
        ticket['segment_num'] = segments.size-1

=begin
					STDERR.puts ""
					for key,val in ticket.as_json do
						STDERR.puts "#{key}: #{val}"
					end
=end
        unless ticket.save! then
          raise MyCustomError, "新規チケットの発行に失敗しました"
        end
        count = count + 1

      end
    end
    return count

  end

  def generate_meta_tags(ticket,current_task,user)
    meta_tags = {}
    puts @@util_funcs
    meta_tags[:min_work_time] = @@util_funcs[:time2sec].call(@@config[:min_work_time]).to_s



    # これはむしろ，普通のtaskでも表示すべき
    meta_tags[:blob_path] = File.dirname(ticket['blob_path'])
    meta_tags[:current_segment] = ticket[:blob_id].split(':')[-1].to_i
    meta_tags[:verbs] = Task2::synonyms[:verb]
    meta_tags[:blob_id] = ticket[:blob_id]
    blob_id_common_part = meta_tags[:blob_id].split(':')[0...-1].join(':')

    meta_tags[:fixed_labels] = {}
    tickets = Ticket.where(task:@task,blob_id:/#{blob_id_common_part}:.+/,completion:true)
    other_tasks = MicroTask.where(task:@task,blob_id:/#{blob_id_common_part}:.+/)
    tickets.each{|t|
      completed_tasks = other_tasks.where(blob_id:t.blob_id)
      if completed_tasks.empty? then
        t.completion = false
        t.update!
        next
        #return "ERROR: empty micro task for completed ticket (blob_id:#{t.blob_id})"
      end

      label = completed_tasks[0]['label']
      meta_tags[:fixed_labels][t['blob_id'].split(':')[-1].to_i] = label
    }

    return MyTask::generate_meta_tags_base(meta_tags,ticket,current_task,user)
  end

  def parse_annotation(hash)
    return {label:hash[:label]}
  end


end