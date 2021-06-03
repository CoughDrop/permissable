require 'json'

module Permissable
  ALL_SCOPES = ['full']
  def self.add_scope(str)
    ALL_SCOPES.push(str)
  end
  
  def self.set_redis(redis, cache_token)
    @permissions_redis = redis
    @cache_token = cache_token
  end
  
  class FakeRedis
    def setex(*args)
      puts "REDIS NOT CONFIGURED, required by Permissable"
      false
    end
    
    def get(*args)
      puts "REDIS NOT CONFIGURED, required by Permissable"
      nil
    end
    
    def del(*args)
      puts "REDIS NOT CONFIGURED, required by Permissable"
      false
    end
  end
  
  def self.permissions_redis
    @permissions_redis ||= FakeRedis.new
    @permissions_redis
  end
  
  def self.cache_token
    # used to quickly invalidate the entire cache
    @cache_token ||= 'permissable_redis_cache_token'
    @cache_token
  end
  
  module InstanceMethods
    def cache_key(prefix=nil)
      id = self.id || 'nil'
      updated = (self.updated_at || Time.now).to_f
      key = "#{self.class.to_s}#{id}-#{updated}:#{Permissable.cache_token}"
      if prefix
        key = prefix + "/" + key
      end
      key
    end
    
    def set_cached(prefix, data, expires=nil)
      expires ||= 1800 # 30 minutes
      Permissable.permissions_redis.setex(self.cache_key(prefix), expires, data.to_json)
    end
  
    def get_cached(prefix)
      cache_string = Permissable.permissions_redis.get(self.cache_key(prefix))
      cache = nil
      if cache_string
        cache = JSON.parse(cache_string) rescue nil
      end
      cache
    end
  
    def clear_cached(prefix)
      Permissable.permissions_redis.del(self.cache_key(prefix))
    end
  
    def allows?(user, action, relevant_scopes=nil)
      relevant_scopes ||= user.permission_scopes if user && user.respond_to?(:permission_scopes)
      relevant_scopes ||= self.class.default_permission_scopes
      relevant_scopes += ['*'] unless relevant_scopes == ['none']
      if self.class.allow_cached_permissions
        # check for an existing result keyed off the record's id and updated_at
        permissions = permissions_for(user, relevant_scopes)
        action.instance_variable_set('@scope_rejected', permissions[action] == false)
      
        return permissions[action] == true
      end

      scope_rejected = false    
      self.class.permissions_lookup.each do |actions, block, allowed_scopes|
        next unless actions.include?(action.to_s)
        next if block.arity == 1 && !user
        res = instance_exec(user, &block)
        if res == true
          if (allowed_scopes & relevant_scopes).length > 0
            return true
          else
            scope_rejected = true
          end
        end
      end
      action.instance_variable_set('@scope_rejected', !!scope_rejected)
      return false
    end
  
    def permissions_for(user, relevant_scopes=nil)
      relevant_scopes ||= user.permission_scopes if user && user.respond_to?(:permission_scopes)
      relevant_scopes ||= self.class.default_permission_scopes
      relevant_scopes += ['*'] unless relevant_scopes == ['none']
      if self.class.allow_cached_permissions
        cache_key = (user && user.cache_key) || "nobody"
        cache_key += "/scopes_#{relevant_scopes.join(',')}"
        permissions = get_cached("permissions-for/#{cache_key}")
        return permissions if permissions
      end

      granted_permissions = {
        'user_id' => (user && user.global_id)
      }
      granted_permissions.with_indifferent_access if granted_permissions.respond_to?(:with_indifferent_access)
      
      self.class.permissions_lookup.each do |actions, block, allowed_scopes|
        already_granted = granted_permissions.keys
        next if block.arity == 1 && !user
        next if actions - already_granted == []
        if instance_exec(user, &block)
          actions.each do |action|
            if (allowed_scopes & relevant_scopes).length > 0
              granted_permissions[action] = true
            else
              granted_permissions[action] ||= false
            end
          end
        end
      end
      # cache the result with a 30-minute expiration keyed off the id and updated_at
      set_cached("permissions-for/#{cache_key}", granted_permissions) if self.class.allow_cached_permissions
      granted_permissions
    end
    
    def self.included(base)
      base.define_singleton_method(:included) do |klass|
        klass.cattr_accessor :permissions_lookup
        klass.cattr_accessor :allow_cached_permissions
        klass.cattr_accessor :default_permission_scopes
        klass.default_permission_scopes = ['full']
        klass.permissions_lookup = []
      end
    end
  end
  
  module ClassMethods
    def cache_permissions
      self.allow_cached_permissions = true
    end
    
    def add_permissions(*actions, &block)
      scopes = ['full']
      if actions[-1].is_a?(Array)
        scopes += actions.pop
      end
      self.permissions_lookup << [actions.map(&:to_s), block, scopes.sort.uniq]
    end
  end
end