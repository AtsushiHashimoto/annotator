require 'mongoid'
#require 'mongoid-versioning'
require 'bcrypt'

class TicketPool
	include Mongoid::Document
=begin
  1. タスクプールを作る
  DONE: /refresh_task_pool → プールに追加
  DONE: passback → チェックをプールに追加
  completion->trueにするときにプールからタスクを削除, pass_backにするときにtask->checkへ移動
  2. checkの自動表示，排他制御，chainを入れる
  #task_poolで今，誰がやっているか(いつ始めたかも)入れる
  #task_poolで最大何人が同時にやれるかを見る．
  # task x ディレクトリかなにかでtask_poolを整列させておく．
  # task_poolにcheck作業と通常taskの別を入れる．
=end

  field :users, type: Hash
  field :max_user_num, type: Integer
  field :pool_type
  field :task
  field :subtask
  field :tickets, type: Hash

  validates :task, presence: true
  validates :pool_type, presence: true
	validates :max_user_num, presence: true
	validates :tickets, presence: true

  def self.generate(pool_type,max_user_num,task,subtask=nil)
    max_user_num = 1 if max_user_num < 1
    return TicketPool.new(
        users:Hash.new{|hash,key|hash[key]={}},
        pool_type:pool_type,
        max_user_num:max_user_num,
        task:task,
        subtask:subtask,
        tickets:{})
  end

  def self.select(user_name, chain_duration_sec)
    STDERR.puts "TicketPool.select(#{user_name}, #{chain_duration_sec})"
    tps = TicketPool.all
    # TicketPoolの要素をランダムな順番で選ぶ
    random_index = (0...tps.count).to_a.shuffle
    # まず，TicketPoolをランダムに選択
    for i in random_index do
      tp = tps[i]
      active_user_num = 0
      for key in tp[:users].keys do
        # 一定時間経過するまでは，特定のユーザが作業をしているとみなす．
        next if key==user_name
        next if !tp.is_active?(key,chain_duration_sec)

        active_user_num = active_user_num + 1
      end
      STDERR.puts "next if #{active_user_num} >= #{tp.max_user_num}"

      next if active_user_num >= tp.max_user_num

      # TicketPoolが決まったら
      tp.assign(user_name)
      t_id = tp.next_task(user_name)
      next if nil == t_id
      return tp, t_id
    end
    # 最後までいったら，何も見つからなかったとしてnil,nilを返す
    return nil, nil
  end

  def is_active?(user_name,chain_duration_sec)
    return false if self.users.empty?
    return false unless self.users.include?(user_name)
    STDERR.puts "is_active?"
    STDERR.puts "#{Time.now} <= #{self.users[user_name][:start_time] + chain_duration_sec}"
    STDERR.puts "(#{self.users[user_name][:start_time]} + #{chain_duration_sec})"
    return Time.now <= self.users[user_name][:start_time] + chain_duration_sec
  end

  def assign(user_name)
    self.users[user_name] = {} unless self.users.has_key?(user_name)
    hash = self.users[user_name]
    puts "hash: #{hash}"
    hash[:start_time] = Time.new
    hash[:last_task] = nil
  end

  def next_task(user_name)
    # {name:username,next_key:key}
    hash = self.users[user_name]
    lt = hash[:last_task]
#    puts "prev. last_task: #{lt}"
    hash[:last_task] = nil if lt and !self.tickets.has_key?(lt)
    lt = hash[:last_task]
    # 最初の(typeがtaskの時は自分がまだやったことのない)タスクを探す．
    flag = (nil == lt)

    for index, t_id in self.tickets do
      puts index
      next if !flag and index != lt # 要チェック
      flag = true
      next if index == lt
      next if self.pool_type == :task and Ticket.find(t_id).annotator.include?(user_name)
      hash[:last_task] = index
      STDERR.puts "ERROR: failed to save pool" unless self.save!
      return t_id
    end
    return nil
  end

  def delete_ticket(ticket_id)
    key = self.tickets.key(ticket_id)
    self.tickets.delete(key)
    return :go_on unless self.tickets.empty?

    # 自身を削除する
    TicketPool.where(_id:self._id).delete
    return :get_empty
  end

  def self.ticket_id2key(ticket_id)
    extname = File.extname(ticket_id)
    return "#{File.dirname(ticket_id)}/#{File.basename(ticket_id,extname)}"
  end

  # :taskから消去して:checkへ移動→ソートしなおし．
  def task2check(ticket_id)
    self.tickets.index(ticket_id)
    self.tickets.delete(key)

    puts "ERROR: check pool called function 'task2check'." if self.pool_type == :check
    check_pool = TicketPool.where(task:self.task,'pool_type'=>:check,subtask:self.subtask) # 複数にsubtaskを分解した場合はここをいじる必要

    if check_pool.count == 1 then
      puts "#{__FILE__}: #{__LINE__}"
      tp = check_pool[0]
      tp.tickets[key] = ticket_id
      # あっているかどうか要確認
      puts tp.tickets
      tp.tickets = Hash[*(tp.tickets.sort.flatten)]
      puts tp.tickets
      puts tp.to_json
    elsif check_pool.count == 0 then
      puts "#{__FILE__}: #{__LINE__}"
      tp = TicketPool.generate(:check,1,self.task,self.subtask)
      tp.tickets[key] = ticket_id
      puts tp.to_json
    else
      STDERR.puts "ERROR: unexpected error. more than 1 check_pool are found."
    end


    STDERR.puts "ERROR: failed to update ticket pool." unless tp.update!

    return :go_on unless self.tickets.empty?

    # 自身を削除する
    TicketPool.where(_id:self._id).delete
    return :get_empty
  end

end
