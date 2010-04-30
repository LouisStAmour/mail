# encoding: utf-8

module Mail
  # The Pop3 retriever allows to get the last, first or all emails from a POP3 server.
  # Each email retrieved (RFC2822) is given as an instance of +Message+.
  #
  # While being retrieved, emails can be yielded if a block is given.
  # 
  # === Example of retrieving Emails from GMail:
  # 
  #   Mail.defaults do
  #     retriever_method :pop3, { :address             => "pop.gmail.com",
  #                               :port                => 995,
  #                               :user_name           => '<username>',
  #                               :password            => '<password>',
  #                               :enable_ssl          => true }
  #   end
  # 
  #   Mail.all    #=> Returns an array of all emails
  #   Mail.first  #=> Returns the first unread email
  #   Mail.last   #=> Returns the first unread email
  # 
  # You can also pass options into Mail.find to locate an email in your pop mailbox
  # with the following options:
  # 
  #   what:  last or first emails. The default is :first.
  #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
  #   count: number of emails to retrieve. The default value is 10. A value of 1 returns an
  #          instance of Message, not an array of Message instances.
  # 
  #   Mail.find(:what => :first, :count => 10, :order => :asc)
  #   #=> Returns the first 10 emails in ascending order
  # 
  class IMAP
    require 'net/imap'

    def initialize(values)
      self.settings = { :address              => "localhost",
                        :port                 => 110,
                        :user_name            => nil,
                        :password             => nil,
                        :enable_ssl           => false }.merge!(values)
    end
    
    attr_accessor :settings
    
    # Get the oldest received email(s)
    #
    # Possible options:
    #   count: number of emails to retrieve. The default value is 1.
    #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #
    def first(options = {}, &block)
      options ||= {}
      options[:what] = :first
      options[:count] ||= 1
      find(options, &block)
    end
    
    # Get the most recent received email(s)
    #
    # Possible options:
    #   count: number of emails to retrieve. The default value is 1.
    #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #
    def last(options = {}, &block)
      options ||= {}
      options[:what] = :last
      options[:count] ||= 1
      find(options, &block)
    end
    
    # Get all emails.
    #
    # Possible options:
    #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #
    def all(options = {}, &block)
      options ||= {}
      options[:count] = :all
      find(options, &block)
    end
    
    # Get folders from imap implementation of http://github.com/kbaum/mail/
    def folders
      start do |imap|
        imap.list("*", "*").collect(&:name)
      end
    end
    
    # Find emails in a POP3 mailbox. Without any options, the 5 last received emails are returned.
    #
    # Possible options:
    #   what:  last or first emails. The default is :first.
    #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #   count: number of emails to retrieve. The default value is 10. A value of 1 returns an
    #          instance of Message, not an array of Message instances.
    #
    def find(options = {}, &block)
      options = validate_options(options)
      
      start do |imap|
        imap.select(options[:mailbox])
        uids = imap.uid_search(options[:query].split(" "))
        
        uids.reverse! if options[:what] == :first
        uids = uids.first(options[:count]) if options[:count].is_a? Integer
        
        if options[:what].to_sym == :last && options[:order].to_sym == :desc ||
           options[:what].to_sym == :first && options[:order].to_sym == :asc ||
          uids.reverse!
        end
        
        if uids.blank?
          return []
        end

        mails = imap.uid_fetch(uids, 'RFC822').
          map! do |m|
            mail = Mail.new(m.attr['RFC822'])
            yield mail if block_given?
            mail
          end

        imap.uid_store(uids, "+FLAGS", [:Seen])

        mails
      end
    end
    
  private
  
    # Set default options
    def validate_options(options)
      options ||= {}
      options[:count]   ||= 10
      options[:order]   ||= :asc
      options[:what]    ||= :first
      options[:mailbox] ||= 'INBOX'
      options[:query]   ||= 'ALL'
      options
    end
  
    # Start a POP3 session and ensures that it will be closed in any case.
    def start(config = Mail::Configuration.instance, &block)
      raise ArgumentError.new("Mail::Retrievable#start takes a block") unless block_given?

      imap = Net::IMAP.new(settings[:address], settings[:port], settings[:enable_ssl])
      imap.login(settings[:user_name], settings[:password])

      yield imap
    ensure
      if defined?(imap) && imap
        imap.logout
      end
    end
  
  end
end