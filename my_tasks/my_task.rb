ANNOTATE_ROOT = File.dirname(File.dirname(__FILE__))

class MyTask
  def parse_hash(config)
    for key,val in config do
      next unless val.kind_of?(String)
      val.gsub!('$ANNOTATE_ROOT', ANNOTATE_ROOT)
      config[key] = val
    end
    return config.with_indifferent_access
  end
end