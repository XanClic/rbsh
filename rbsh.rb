#!/usr/bin/ruby
# coding: utf-8

require 'readline'


class PipeLine
    def initialize(pre, post)
        @line = [pre, post.kind_of?(PipeLine) ? post.to_a : post].flatten
    end

    def to_a
        @line
    end

    def inspect
        "#<PipeLine:#{to_a.inspect}>"
    end

    def method_missing(m, *a)
        @line.send(m, *a)
    end
end


class CommandLine
    def initialize(pre, post)
        @line = [pre, post.map { |e| e.kind_of?(CommandLine) ? e.to_a : e }].flatten
    end

    def to_a
        @line
    end

    def inspect
        "#<CommandLine:#{to_a.inspect}>"
    end

    def | target
        return PipeLine.new(self, target)
    end

    def -@
        @line[0] = "-#{@line[0]}"
    end

    def to_ary
        nil
    end

    def method_missing m
        @line[-1] = "#{@line[-1]}.#{m.to_s}"
    end
end


$aliases = Hash.new


def method_missing(m, *a)
    return nil if m.to_s.start_with? 'to_'
    CommandLine.new(m.to_s, a)
end


def cd(*args)
    dir = nil
    p = false
    l = false
    curpath = ''

    while !args.empty?
        arg = args.shift

        if arg[0] == '-'
            case arg
            when '-P'
                p = true
            when '-L'
                l = true
            else
                throw "Bad argument #{arg}"
            end
        elsif !dir
            dir = arg
        else
            throw "Bad argument #{arg}"
        end
    end

    if !dir
        dir = ENV['HOME'] ? ENV['HOME'] : '/'
    end

    components = dir.split '/'

    # FIXME
    if dir[0] == '~' && ENV['HOME']
        dir = ENV['HOME'] + dir[1..-1]
    end

    if dir[0] == '/'
        curpath = dir
    elsif components[0] == '.' || components[0] == '..'
        curpath = dir
    elsif ENV['CDPATH']
        curpath = ENV['CDPATH'].split(':').map { |p|
            p = p.empty ? '.' : p
            "#{p}#{p[-1] == '/' ? '' : '/'}#{dir}"
        }.find { |p| File.directory? p }
    end

    curpath = dir if curpath.empty?

    unless p
        pwd = Dir.pwd
        curpath = "#{pwd}#{pwd[-1] == '/' ? '' : '/'}#{curpath}" unless curpath[0] == '/'

        components = curpath.split '/'
        i = 0
        while components[i]
            if components[i] == '.'
                components.delete_at i
            elsif components[i] == '..' && i > 0
                components.delete_at i
                components.delete_at i - 1
                i -= 1
            else
                i += 1
            end
        end

        curpath = components.flatten * '/'
    end

    Dir.chdir(curpath)

    ENV['OLDPWD'] = ENV['PWD']
    ENV['PWD'] = curpath
end


load '.rbshrc'


$procres = nil

while true
    line = Readline.readline(eval("\"#{$PS1}\""))
    exit 0 unless line

    begin
        result = eval(line)
    rescue SyntaxError
        cmd = line.split
        result = CommandLine.new(cmd[0], cmd[1..-1])
    end

    result = PipeLine.new(result, []) if result.kind_of? CommandLine

    if result.kind_of? PipeLine
        len = result.length

        stdin = nil

        pids = result.map.with_index do |cl, i|
            cl = cl.to_a
            cmd  = $aliases[cl[0]] ? $aliases[cl[0]] : cl[0]
            pars = cl[1..-1]

            if cmd.kind_of? Array
                pars = cmd[1..-1] + pars
                cmd = cmd[0]
            end

            if i == len - 1
                stdout = nstdin = nil
            else
                nstdin, stdout = IO.pipe
            end

            pid = fork do
                $stdin.reopen(stdin) if stdin
                $stdout.reopen(stdout) if stdout

                Kernel.exec(cmd, *pars)
            end

            stdout.close if stdout
            stdin.close if stdin

            stdin = nstdin

            pid
        end

        $procres = pids.map { |p| Process.wait p; $? }[-1]
    else
        puts "=> #{result.inspect}"
        $procres = nil
    end
end
