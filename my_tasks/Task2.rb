class Task2 < MyTask
  def initialize(config={})
    @task = self.class.name.underscore
    super(@task)
    @@config = generate_config(config)
    @@config['synonyms'] = load_synonyms(@@config['synonym_file']) if @@config.include?('synonym_file')
  end
  def self.synonyms
    @@config[:synonyms]
  end
  def load_synonyms(synonym_file)
    hash = Hash.new{|h,k| h[k] = []}
    File.open(synonym_file).each{|line|
      type, value, description = line.split("\t").map{|v|v.strip}
      type = type.split("-")[0]
      case type
        when '材料'
          type = :ingredient
        when '調味料'
          type = :seasoning
        when '調理器具'
          type = :utensil
        when '動作'
          hash[:verb] << [value,description]
          next
      end
      hash[type] << "#{description}"
    }
    hash
  end
  def check_recipe_files(path)
    flag = true;
    # レシピディレクトリの中に必要なファイルが揃っているかを確認する
    if Dir.glob("#{path}/overview.*").empty? then
      flag = false
      STDERR.puts "overview.jpgがありません"
    end
    if Dir.glob("#{path}/*.csv").empty? then
      flag = false
      STDERR.puts "形態素解析結果がありません"
    end
    flag
  end

  def generate_tickets
    all_blobs = Dir.glob(@@config[:data_path] + @@config[:glob_pattern]).sort
    # task2の生成
    count = 0

    for blob_path in all_blobs do
      md = blob_path.match(@@config[:blob_id_regex])
      next unless md
      recipe_id = md[1].gsub("/",":")
      blob_full_path = blob_path.clone
      blob_path.sub!(@@config[:data_path],'')

      next unless check_recipe_files(blob_full_path)

      # 既に登録があれば再生成や上書きはしない
      _id = "#{@task}_#{recipe_id}"
      next if Ticket.duplicate?(_id)

      count = count + 1
      ticket = Ticket.new(_id: _id, blob_id: recipe_id, task: @task, blob_path: blob_path, annotator:[])

      # 食材，調理器具，調味料の候補を入れる．
      ticket[:candidates] = load_nlp_result_csv(blob_full_path)

      unless ticket.save! then
        raise MyCustomError, "新規チケットの発行に失敗しました"
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