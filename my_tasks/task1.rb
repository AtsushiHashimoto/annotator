class Task1 < MyTask
  def initialize(config={})
    @@config = parse_hash(config)
    @task = self.class.name.underscore
    super(@task,@@config)
  end

  def generate_tickets
    puts @@config

    puts @@config[:data_path] + @@config[:glob_pattern]
    all_blobs = Dir.glob(@@config[:data_path] + @@config[:glob_pattern]).sort
    # task1の生成
    count = 0
    for blob_path in all_blobs do
      puts blob_path
      puts @@config[:blob_id_regex]

      md = blob_path.match(@@config[:blob_id_regex])
      puts blob_path
      next unless md
      blob_id = md[1].gsub("/",":")
      blob_path.sub!(@@config[:data_path], '')

      # before imageなどの登録
      regex = '(.*\/)extract\/(.+\/).+\/\w+_(\d{7})_\d{3}(.png)'
      md = blob_path.match(regex);
      unless md then
        STDERR.puts "Error: failed to parse blob_path into original image path"
        STDERR.puts "blob_path: '#{blob_path}'"
        STDERR.puts "regex: '#{regex}'"
        next
      end

      # 既に登録があれば再生成や上書きはしない
      _id = "#{@task}_#{blob_id}"
      next if Ticket.duplicate?(_id)
      ticket = Ticket.new(_id: _id, blob_id: blob_id, task: @task, blob_path: blob_path, annotator: [])


      after_image = md[1..-1].join()
      ticket[:after_image] = after_image
      before_image_path = get_prev_file(@@config[:data_path] + after_image)
      next if before_image_path == nil
      # 本当はここでnilなら背景画像を返すようにする
      ticket[:before_image] = before_image_path.sub(@@config[:data_path], '')

      count = count + 1

      unless ticket.save! then
        raise MyCustomError, "新規チケットの発行に失敗しました"
      end
    end
    return count

  end

  def get_prev_file(path)
    dir = File.dirname(path)
    basename = File.basename(path)
    common_dir = File.dirname(dir)
    camera_name = File.basename(dir)
    return common_dir + "/BG/" + camera_name + "/bg_" + basename
  end



end