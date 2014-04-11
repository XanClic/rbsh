#!/usr/bin/ruby
# coding: utf-8

require 'readline'


class ProgResult
    def initialize(res)
        $res = res
    end

    def res
        $res
    end
end


$aliases = Hash.new


def run(cmd, *pars)
    cmd = $aliases[cmd] ? $aliases[cmd] : cmd

    if cmd.kind_of? Array
        pars = cmd[1..-1] + pars if cmd.length > 1
        cmd = cmd[0]
    end

    pid = fork do
        Kernel.exec(cmd, *pars)
    end

    Process.wait(pid)

    return ProgResult.new $?
end


def method_missing(m, *args)
    fn = m.to_s

    return nil if fn.start_with? 'to_'

    if fn.include? '/'
        throw NoMethodError unless File.file? fn
    else
        throw NoMethodError unless ENV['PATH'].split(':').find { |p| File.file? "#{p}/#{fn}" }
    end

    run(fn, *args)
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

    result = eval(line)

    if result.kind_of?(ProgResult)
        $procres = result.res
    else
        puts "=> #{result.inspect}"
        $procres = nil
    end
end
