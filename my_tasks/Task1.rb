class Task1 < MyTask
  def initialize(config={})
    @task = self.class.name.underscore
    super(@task)
    @@config = generate_config(config)
  end

  def generate_tickets
    #puts @@config[:data_path] + @@config[:glob_pattern]
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

  def generate_meta_tags(ticket,current_task,user)
    meta_tags = {}
    puts @@util_funcs
    meta_tags[:min_work_time] = @@util_funcs[:time2sec].call(@@config[:min_work_time]).to_s

    meta_tags[:image_width] = @@config[:image_width]
    meta_tags[:image_height] = @@config[:image_height]
    meta_tags[:diff_image] = generate_diff_image(ticket[:after_image],ticket[:before_image], ticket[:blob_path]);
    meta_tags[:mask_image] = generate_mask_image(ticket[:blob_path])
    return MyTask::generate_meta_tags_base(meta_tags,ticket,current_task,user)
  end

  def parse_annotation(hash)
    annotation = {}
    unless hash[:annotation].empty? then
      # 空でなければtask1 の結果をパースして保存
      if hash[:annotation] == 'null' then
        array = []
      else
        array =  JSON.parse(hash[:annotation]).uniq
      end
      #画像のサイズで正規化しておく．
      for i in 0...array.length do
        array[i] = array[i].with_indifferent_access
        array[i][:x] = array[i][:x].to_f / @@config[:image_width]
        array[i][:width] = array[i][:width].to_f / @@config[:image_width]
        array[i][:y] = array[i][:y].to_f / @@config[:image_height]
        array[i][:height] = array[i][:height].to_f / @@config[:image_height]
      end
      annotation[:annotation] = array
    end
    return annotation
  end

  # task1の補助関数
  def get_prev_file(path)
    dir = File.dirname(path)
    basename = File.basename(path)
    common_dir = File.dirname(dir)
    camera_name = File.basename(dir)
    return common_dir + "/BG/" + camera_name + "/bg_" + basename
  end
  def generate_diff_image(_image1,_image2, orig_blob_path)
    image1 = @@config[:data_path] + _image1
    image2 = @@config[:data_path] + _image2
    dir = @@config[:data_path] + File.dirname(orig_blob_path).sub('extract','diff')
    `mkdir -p #{dir}`
    output_image1 = "#{dir}/#{File.basename(image1)}"
    unless File.exist?(output_image1) then
      output_image2 = "#{dir}/image2_#{File.basename(image1)}"
      `composite -compose difference #{image1} #{image2} #{output_image1}`
      `composite -compose difference #{image2} #{image1} #{output_image2}`
      `composite -compose add #{output_image1} #{output_image2} #{output_image1}`
      `convert #{output_image1} -colorspace Gray -modulate #{@@config[:modulation]} #{output_image1}`
      `rm #{output_image2}`
    end
    return output_image1.sub(@@config[:data_path],"")
  end
  def generate_mask_image(blob_image)
    path = @@config[:data_path] + blob_image
    dir = File.dirname(path).sub('extract','mask')
    `mkdir -p #{dir}`
    output_image = "#{dir}/#{File.basename(path)}"

    unless File.exist?(output_image)
      `convert -type GrayScale -threshold 1 #{path} #{output_image}`
    end

    return output_image.sub(@@config[:data_path],"")
  end

end