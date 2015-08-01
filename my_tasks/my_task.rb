ANNOTATE_ROOT = File.dirname(File.dirname(__FILE__))

class MyTask
  def initialize(task_name,config)
    @name = task_name
    @config = config
  end

  def parse_hash(config)
    for key,val in config do
      next unless val.kind_of?(String)
      val.gsub!('$ANNOTATE_ROOT', ANNOTATE_ROOT)
      config[key] = val
    end
    return config.with_indifferent_access
  end

  def has_enough_microtasks(ticket,min_tasks)
    #puts "#{min_tasks} <= #{ticket.annotator.size}"
    return true if min_tasks <= ticket.annotator.size
    return false
  end

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
end