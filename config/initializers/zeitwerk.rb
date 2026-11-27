# lib/life_gamble/cpu_ai.rb は LifeGamble::CpuAI を定義しているため、
# 既定の推測（CpuAi）ではなく CpuAI として読み込ませる
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("cpu_ai" => "CpuAI")
end
