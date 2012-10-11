require 'octokit'
require 'write_xlsx'
require 'optparse'
require 'highline/import'
require 'date'
require 'yaml'

module Connector
  def client
    unless defined?(@client)
      options = {:per_page => 100, :auto_traversal => true}
      if self.get_auth.empty?
        username = ask("GitHub Username  ")
        password = ask("GitHub Password  ") {|q| q.echo ="*"}
        options.merge!({:login => username, :oauth_token => password })
      else
        options.merge!({:login => self.get_auth.first, :oauth_token => self.get_auth.last}) 
      end
      @client = Octokit::Client.new(options)
    end
    @client
  end
  
  def get_auth(path="")
    # load the authentication info and return it
    # TODO: Allow password auth (maybe?)
    # TODO: Prompt if file not found
    if path == ""
      cf_file = File.join(File.dirname(__FILE__), '..', 'config', 'octokit.yml')
    else
      cf_file = path 
    end
    if File.exist?(cf_file) 
      config = YAML::load_file(cf_file)
      [config['login'], config['oauth_token']]
    else
      []
    end
  end
  
end

class ReportBook
  # should use write_date_time, but can't be arsed fixing it's date_time implementation
  def initialize(name)
    @book = WriteXLSX.new("#{name}.xlsx")
    @sheet = nil
    @row = 0
    @formats = {}
  end
  
  def bold_face
    unless @formats.has_key?("bold_face")
      boldface = @book.add_format
      boldface.set_bold
      boldface.set_align('left')
      @formats["bold_face"] = boldface
    end
    @formats["bold_face"]
  end
  
   
  def add_worksheet(name)
    name.gsub!("/", "-")
    @sheet = @book.add_worksheet(name)
    @row = 0 
  end
  
  def write_row(row_contents)
    # write the contents of the row without format 
    row_contents.each_with_index do |content, index|
      if content.is_a?(DateTime)
        @sheet.write_string(@row, index, content.strftime("%F %R"))
      else
        @sheet.write_string(@row, index, content.to_s)
      end
    end
    @row += 1
  end
  
  def write_header_row(row_contents)
    # row_contents all bold
    row_contents.each_with_index do |content, index|
      if content.is_a?(DateTime)
        @sheet.write_string(@row, index, content.strftime("%F %R"), bold_face)
      else
        @sheet.write_string(@row, index, content.to_s, bold_face)
      end
    end
    @row += 1
  
  end
  
  def add_space
    @row += 1
  end
  
  def write_title_row(row_contents)
    # row_contents, first bold, remainder non-bold
    if row_contents.include?(nil)
      puts "Nil in #{row_contents}"
    end
    row_contents.each_with_index do |content, index|
      if content.nil?
        content = ""
      end
      if content.is_a?(DateTime)
        if index == 0
          @sheet.write_string(@row, index, content.strftime("%F %R"), bold_face)
        else
          @sheet.write_string(@row, index, content.strftime("%F %R"))
        end
      else
        if index == 0
          @sheet.write_string(@row, index, content.to_s, bold_face)
        else
          @sheet.write_string(@row, index, content.to_s)
        end
      end
    end
    @row += 1
  end
  
  def close
    @book.close
  end
  
end

class PullRequestReporter
  include Connector

  def initialize(repository)
    @repository = repository
    @report = []
    @all_pull_requests = []
    @pull_commits = {}
    @branches = []
  end
  
  def scan(branch)
    @branches << branch
    # run a listing for all pull requests against this branch
    # content of this should go into a single tab (named after the branch)
    if @all_pull_requests.empty?
      # only pull this once
      # firstly the open pull requests
      puts "Loading Open Pull Requests for #{@repository}"
      @all_pull_requests = client.pull_requests(@repository).collect {|pr| PullRequest.new(pr)}
      puts "Loading Closed Pull Requests for #{@repository}"
      @all_pull_requests.concat(client.pull_requests(@repository, state="closed").collect {|pr| PullRequest.new(pr)})
    end

  end
  
  def export
    # write the report
    puts "Reporting on #{@repository}"
    work_book = ReportBook.new("pull_request_report_for_#{@repository.gsub('/', '_')}")
    @branches.each do |branch|
      puts "Reporting on Pull Requests into #{branch}"
      branchname = branch.split('/').last
      # create a sheet
      work_book.add_worksheet(branchname)
      work_book.write_title_row(["Repository", @repository])
      work_book.write_title_row(["Branch", branch])
      work_book.write_title_row(["Report generated", DateTime.now])
      work_book.add_space
      work_book.write_title_row(["Pull Requests into #{branch}"])
      branch_pulls = @all_pull_requests.select {|x| x.branch == branch}
      branch_pulls.sort.each do |pull|
        puts "Adding Pull Request #{pull.title} (#{pull.number})"
        # iterate over pull requests into branch of interest
        work_book.write_title_row(["Pull request name", pull.title])
        work_book.write_title_row(["Pull request body", pull.body])
        work_book.write_title_row(["Pull request number", pull.number])
        work_book.write_title_row(["Raised by", pull.created_by])
        work_book.write_title_row(["Date Raised", pull.creation_date])
        work_book.write_title_row(["Merged by", pull.merged_by])
        work_book.write_title_row(["Date Merged/Closed", pull.end_date])
        work_book.write_title_row(["Number of files changed", pull.changed_files])
        work_book.write_title_row(["Number of additions", pull.additions])
        work_book.write_title_row(["Number of deletions", pull.deletions])
        work_book.write_title_row(["Number of commits", pull.number_of_commits])
        if pull.comments.empty?
          work_book.write_title_row(["Comments on Pull Request", "No Comments on Pull Request"])
        else
          work_book.write_title_row(["Comments on Pull Request"])
          work_book.write_header_row(["Date", "Commenter", "File", "Line", "Comment"])
          pull.comments.sort.each do |comment|
            work_book.write_row(comment.as_array)
          end
        end
        work_book.add_space
        work_book.write_title_row(["Commits in the Pull Request"])
        pull.commits.sort.each do |commit|
          work_book.write_header_row(["SHA", "Created by", "Created on", "Message"])
          work_book.write_row([commit.sha, commit.committer, commit.created, commit.message])
          unless commit.comments.empty?
            work_book.write_title_row(["Comments on commit"])
            work_book.write_header_row(["Date", "Commenter", "File", "Line", "Comment"])
            commit.comments.sort.each do |comment|
              work_book.write_row(comment.as_array)
            end
          end
        end
        work_book.add_space
      end
    end
    work_book.close
  end
 
  
end

class PullRequest
  include Connector

  def initialize(pull_request)
    # this is the set from repo.pull_requests
    @pull_request = pull_request 
    # this is the set from client.pull_request - lazy load this 
    @target = nil
    # this looks weird, but you can genuinely not have comments, so checking for nil is safer than checking for empty
    @commits = nil
    @comments = nil
  end
  
  def <=>(other)
    self.creation_date <=> other.creation_date
  end
  
  def contributors
    #list all people who took part in pull request + commits therein
    contributors = []
    @commits.each do |commit|
      # creator of the commit
      if commit[:committer].nil?
        # anon commit
        unless contributers.include?(commit[:commit][:committer][:name])
          contributers << commit[:commit][:committer][:name]
        end
      else
        unless contributers.include?(commit[:committer][:login])
          contributers << commit[:committer][:login]
        end
      end
      commit[:comments].each do |comment|
        unless contributers.include?(comment[:user][:login])
          contributers << comment[:user][:login]
        end
      end
    end
    @comments.each do |prcomment|
      unless contributers.include?(prcomment[:user][:login])
        contributers << prcomment[:user][:login]
      end
    end
    contributers
  end
  
  def is_closed?
    state == "closed"
  end
  
  def state
    @pull_request[:state]
  end
  
  def number_of_commits
    if @target.nil?
      @target = client.pull_request(@pull_request[:base][:repo][:full_name], @pull_request[:number])
    end
    @target[:commits]
  end

  def number_of_comments
    if @target.nil?
      @target = client.pull_request(@pull_request[:base][:repo][:full_name], @pull_request[:number])
    end
    @target[:comments]
  end

  def additions
    if @target.nil?
      @target = client.pull_request(@pull_request[:base][:repo][:full_name], @pull_request[:number])
    end
    @target[:additions]
  end

  def deletions
    if @target.nil?
      @target = client.pull_request(@pull_request[:base][:repo][:full_name], @pull_request[:number])
    end
    @target[:deletions]
  end
  
  def changed_files
    if @target.nil?
      @target = client.pull_request(@pull_request[:base][:repo][:full_name], @pull_request[:number])
    end
    @target[:changed_files]
  end
  
  def number
    @pull_request[:number]
  end
  
  def repository
    @pull_request[:base][:repo][:full_name]
  end
  
  def created_by
    @pull_request[:user][:login]
  end
  
  def merged?
    @target[:merged] == true
  end
  
  def merged_by
    if @target.nil?
      @target = client.pull_request(@pull_request[:base][:repo][:full_name], @pull_request[:number])
    end
    if merged?
      @target[:merged_by][:login]
    else
      "Not yet merged"
    end
  end
  
  def title
    # title of the pull request
    @pull_request[:title]
  end
  
  def body
    # body of pull request
    @pull_request.fetch(:body, "")
  end
  
  def head
    # branch of repository into which the pull request is going
    @pull_request[:head][:ref]
  end

  def repository
    # repository into which the pull request is going
    @pull_request[:base][:repo][:full_name]
  end
  
  def creation_date
    DateTime.parse(@pull_request[:created_at])
  end

  def end_date
    if merged_date.nil?
      if closed_date.nil?
        "Not closed or merged"
      else
        closed_date
      end
    else
      merged_date
    end
  end
  
  def closed_date
    DateTime.parse(@pull_request[:closed_at])
  end

  def merged_date
    DateTime.parse(@pull_request[:closed_at])
  end
  
  def branch
    # branch into which PR is going
    @pull_request[:base][:ref]
  end
    
  def commits
    #lazy load
    if @commits.nil?
      @commits = client.pull_request_commits(repository, number).collect {|commit| Commit.new(commit, repository)}
    end
    @commits
  end
  
  def comments
    # lazy load
    if number_of_comments > 0 
      # only try to load these if they exist
      if @comments.nil?
        @comments = client.pull_request_comments(self.repository, self.number).collect {|comment| Comment.new(comment)}
      end
      @comments
    else
      []
    end
  end
  
end

class Commit
  
  include Connector
  
  # a commit for a pull request
  def initialize(commit, repository)
    @commit = commit
    @repository = repository
    @comments = nil
  end
  
  def message
    @commit[:commit][:message]
  end
  
  def committer
    if @commit[:committer].nil?
      @commit[:commit][:committer][:name]
    else
      @commit[:committer][:login]
    end
  end
  
  def <=>(other)
    self.created <=> other.created
  end
  
  def sha
    @commit[:sha]
  end

  def comment_count
    @commit[:commit][:comment_count]
  end
  
  def comments
    if @comments.nil?
      if comment_count > 0
        @comments = client.commit_comments(@repository, sha).collect {|comment| Comment.new(comment)}
      else
        @comments = []
      end
    end
    @comments
  end
  
  def created
    DateTime.parse(@commit[:commit][:committer][:date])
  end
  
end

class Comment
  # two types of comment, commit and pull request
  
  def initialize(comment)
    @comment = comment
  end
  
  def <=>(other)
    # TODO: comparator, by path, then position, then date
    self.created <=> other.created
  end
  
  def as_array
    [created, author, path, position, body]
  end
  
  def id
    # comment id
    @comment[:id]
  end
  
  def author
    @comment[:user][:login]
  end
  
  def created
    DateTime.parse(@comment[:created_at])
  end
  
  def body
    @comment[:body]
  end
  
  def path
    @comment[:path]
  end
  
  def position
    # line number in path
    @comment[:position]
  end

end

if $0 == __FILE__
  options = {:branch => []}
  OptionParser.new do |opts|
    opts.on("-o", "--owner [OWNER]", "Owner of repository") do |owner|
      options[:owner] = owner
    end
    opts.on("-n", "--name [NAME]", "Name of repository") do |name|
      options[:name] = name
    end
    opts.on("-r", "--repository [REPOSITORY]", "Repository name") do |repository|
      options[:repository] = repository
    end
    opts.on("-b", "--branch-name [BRANCH]", "Name of Branch against which report is to be run") do |branch|
      options[:branch] << branch
    end
  end.parse!
  if ((options.has_key?(:owner) && options.has_key?(:name)) || options.has_key?(:repository) && options.has_key?(:branch))
    if (options.has_key?(:owner) && options.has_key?(:name))
      repository = options[:owner] + "/" + options[:name]
    else
      repository = options[:repository]
    end
    reporter = PullRequestReporter.new(repository)
    options[:branch].each do |branch|
      reporter.scan(branch)
    end
    reporter.export
  else
    puts "Need to specify Owner and Name or Repository and Branch"
  end
end