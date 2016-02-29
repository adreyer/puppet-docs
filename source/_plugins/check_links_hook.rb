require 'byebug'
require 'pathname'
require 'puppet_docs/versions'
require 'yaml'

Jekyll::Hooks.register :site, :post_render do |site|
  # byebug
  puts 'hey'
  DOCS_HOSTNAME = 'docs.puppetlabs.com'
  NGINX_CONFIG = "#{site.source}/nginx_rewrite.conf"

  link_test_results = {}
  href_regex = %r{(href)=(['"])([^'"]+)\2}i
  src_regex = %r{(src)=(['"])([^'"]+)\2}i
  redirections = File.read(NGINX_CONFIG).scan(%r{^rewrite\s+(\S+)}).map{|ary| Regexp.new(ary[0]) }

  site.pages.each do |page|
    puts "testing #{page.url}"

    link_test_results[page.relative_path] = {}
    link_test_results[page.relative_path][:internal_with_hostname] = []
    link_test_results[page.relative_path][:broken_path] = []
    link_test_results[page.relative_path][:broken_anchor] = []

    cwd = Pathname.new(page.relative_path).dirname
    links = page.content.scan(href_regex).map{|ary| ary[2]}
    images = page.content.scan(src_regex).map{|ary| ary[2]}

    links.each {|link|
      (path, anchor) = link.split('#', 2)

      if path =~ /:/
        if path =~ /^mailto/ # then we don't care, byeeeee
          next
        elsif path =~ %r{^(https?:)?//} # it's either external, or internal and against our style guidelines
          if path =~ /#{DOCS_HOSTNAME}/ # it's internal!
            link_test_results[page.relative_path][:internal_with_hostname] << link
            # continue and see if it actually resolves. Get the path portion.
            path = path.split(DOCS_HOSTNAME, 2)[1]
          else # it's external and we don't careeeee
            next
          end
        end
      end

      full_path = (cwd + path).to_s

      if full_path =~ %r{/latest/} # then we have to resolve it to its real directory, because we haven't symlinked latest yet.
        path_dirs = full_path.split('/')
        project = path_dirs[ path_dirs.index('latest') - 1 ]
        project_dir = "#{site.source}/#{project}"
        versions = Pathname.glob("#{project_dir}/*").select {|f|
          f.directory?
        }.map {|d| d.basename.to_s}

        latest = site.config['lock_latest'][project] || PuppetDocs::Versions.latest(versions)
        path_dirs[ path_dirs.index('latest') ] = latest
        full_path = path_dirs.join('/')
      end

      # Handle Jekyll's "friendly" index.html URL trimming
      full_path.sub!(%r{/index\.html$}, '/')

      destination = site.pages.detect {|pg| pg.url == full_path or pg.relative_path == full_path}
      if destination.nil? # then the page doesn't exist, but we still gotta check redirects
        unless redirections.detect {|match| full_path =~ match }
          link_test_results[page.relative_path][:broken_path] << link
        end
      end
    }
  end

  puts YAML.dump(link_test_results)
end
