require "formula"
require "tap"
require "thread"

module Readall
  class << self
    def valid_ruby_syntax?(ruby_files)
      ruby_files_queue = Queue.new
      ruby_files.each { |f| ruby_files_queue << f }
      failed = false
      workers = (0...Hardware::CPU.cores).map do
        Thread.new do
          Kernel.loop do
            begin
              # As a side effect, print syntax errors/warnings to `$stderr`.
              failed = true if syntax_errors_or_warnings?(ruby_files_queue.deq(true))
            rescue ThreadError
              break
            end
          end
        end
      end
      workers.each(&:join)
      !failed
    end

    def valid_aliases?(alias_dirs)
      failed = false
      alias_dirs.each do |alias_dir|
        next unless alias_dir.directory?
        alias_dir.children.each do |f|
          next unless f.symlink?
          next if f.file?
          onoe "Broken alias: #{f}"
          failed = true
        end
      end
      !failed
    end

    def valid_formulae?(formulae)
      failed = false
      formulae.each do |file|
        begin
          Formulary.factory(file)
        rescue Interrupt
          raise
        rescue Exception => e
          onoe "Invalid formula: #{file}"
          puts e
          failed = true
        end
      end
      !failed
    end

    def valid_tap?(tap, options = {})
      failed = false
      if options[:aliases]
        valid_aliases = valid_aliases?([tap.alias_dir])
        failed = true unless valid_aliases
      end
      valid_formulae = valid_formulae?(tap.formula_files)
      failed = true unless valid_formulae
      !failed
    end

    private

    def syntax_errors_or_warnings?(rb)
      # Retrieve messages about syntax errors/warnings printed to `$stderr`, but
      # discard a `Syntax OK` printed to `$stdout` (in absence of syntax errors).
      messages = Utils.popen_read("#{RUBY_PATH} -c -w #{rb} 2>&1 >/dev/null")
      $stderr.print messages

      # Only syntax errors result in a non-zero status code. To detect syntax
      # warnings we also need to inspect the output to `$stderr`.
      !$?.success? || !messages.chomp.empty?
    end
  end
end
