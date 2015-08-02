ANNOTATE_ROOT = File.dirname(File.dirname(__FILE__))

class MyTask
  attr_reader :config
  @@util_funcs = {}
  #########################
  # 小クラスがOverrideするべき関数
  def necessary_func(func_name)
    STDERR.puts "A subclass of MyTask must have #{func_name}."
  end
  def generate_tickets
    necessary_func(__method__)
  end
  def generate_tickets
    necessary_func(__method__)
  end
  def generate_meta_tags(ticket,current_task,user)
    necessary_func(__method__)
  end

  #########################
  # viewディレクトリ内のパス
  def view_path_task
    return "contents/#{@name}"
  end
  def view_path_check
    return "check/#{@name}"
  end

  #########################
  # 初期化 == ここから
  def initialize(task_name)
    @name = task_name

  end
  def self.set_default_config(config)
    @@default_config = config
  end
  def self.set_util_funcs(hash={})
    for key,val in hash do
      @@util_funcs[key] = val
    end
  end
  def generate_config(_config)
    config = @@default_config.deep_dup
    @config = parse_hash(config.deep_merge(_config))
    return @config
  end
  def parse_hash(config)
    for key,val in config do
      next unless val.kind_of?(String)
      val.gsub!('$ANNOTATE_ROOT', ANNOTATE_ROOT)
      config[key] = val
    end
    return config.with_indifferent_access
  end
  # 初期化 == ここまで
  #########################


  #########################
  # 終了判定 == ここから
  def has_enough_microtasks(ticket,min_tasks)
    #puts "#{min_tasks} <= #{ticket.annotator.size}"
    return true if min_tasks <= ticket.annotator.size
    return false
  end

  # 終了判定 == ここまで
  #########################


  #########################
  # チケット作成 == ここから
  def refresh_ticket_pool
    puts "refresh_ticket_pool is called"
    hash = Hash.new{|hash,key| hash[key] = {}} # poolの元

    tickets = Ticket.where(task:@task,completion:false)
    pools = []
    return pools if tickets.count() == 0

    puts tickets.count()
    for t in tickets do
      key = File.dirname(t.blob_path)
      value = File.basename(t.blob_path)
      hash[key][value] = t
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
          puts "check"
          pool_check.tickets[index] = t._id
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
  # チケット作成 = ここまで
  #########################

  #########################
  # タスク画面生成 = ここから
  def self.generate_meta_tags_base(tags,ticket,current_task,user)
    base_tags = {}
    base_tags[:_id] = current_task[:id]
    base_tags[:worker] = user
    base_tags[:start_time] = current_task[:start_time];
    return base_tags unless ticket
    base_tags[:blob_id] = ticket[:blob_id]
    for key,val in ticket.as_json do
      # 既にあるハッシュ要素は上書きしない(_id)など
      next unless val
      next if val.respond_to?(:'empty?') and val.empty?
      next if base_tags.include?(key.to_sym)
      base_tags[key.to_sym] = val.to_s
    end

    overwritten_tags = base_tags.keys & tags.keys
    STDERR.puts "WARNING: task-specific meta tags [#{overwritten_tags.join(", ")}] are overwritten. This will cause an Error."
    base_tags.deep_merge!(tags)
  end

  # タスク画面生成 = ここまで
  #########################


end