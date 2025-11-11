# frozen_string_literal: true

# Efficient LRU (Least Recently Used) Cache implementation
# Uses a doubly-linked list and hash map for O(1) operations
#
# This implementation provides:
# - O(1) get operation
# - O(1) put operation
# - O(1) eviction of least recently used item
# - Thread-safe operations
class LruCache
  class Node
    attr_accessor :key, :value, :prev, :next

    def initialize(key, value)
      @key = key
      @value = value
      @prev = nil
      @next = nil
    end
  end

  def initialize(capacity)
    @capacity = capacity
    @cache = {}  # key => Node
    @head = Node.new(nil, nil)  # Dummy head
    @tail = Node.new(nil, nil)  # Dummy tail
    @head.next = @tail
    @tail.prev = @head
    @mutex = Mutex.new  # For thread safety
  end

  # Get value for key, returns nil if not found
  # Moves accessed node to front (most recently used)
  # Time complexity: O(1)
  def get(key)
    @mutex.synchronize do
      return nil unless @cache.key?(key)

      node = @cache[key]
      move_to_front(node)
      node.value
    end
  end

  # Put key-value pair into cache
  # If key exists, update value and move to front
  # If cache is full, evict least recently used item
  # Time complexity: O(1)
  def put(key, value)
    @mutex.synchronize do
      if @cache.key?(key)
        # Update existing node
        node = @cache[key]
        node.value = value
        move_to_front(node)
      else
        # Create new node
        node = Node.new(key, value)
        @cache[key] = node
        add_to_front(node)

        # Evict if over capacity
        if @cache.size > @capacity
          evict_lru
        end
      end
    end
  end

  # Check if key exists in cache
  # Time complexity: O(1)
  def key?(key)
    @mutex.synchronize do
      @cache.key?(key)
    end
  end

  # Get current cache size
  # Time complexity: O(1)
  def size
    @mutex.synchronize do
      @cache.size
    end
  end

  # Clear all entries from cache
  # Time complexity: O(n)
  def clear
    @mutex.synchronize do
      @cache.clear
      @head.next = @tail
      @tail.prev = @head
    end
  end

  # Get all keys in cache (for debugging/testing)
  # Time complexity: O(n)
  def keys
    @mutex.synchronize do
      @cache.keys
    end
  end

  # Check if cache is empty
  # Time complexity: O(1)
  def empty?
    @mutex.synchronize do
      @cache.empty?
    end
  end

  # Get value if exists, otherwise compute using block and cache it
  # Time complexity: O(1) for cache operations, O(block) for computation
  def fetch(key)
    value = get(key)
    return value if value

    return nil unless block_given?

    computed_value = yield
    put(key, computed_value)
    computed_value
  end

  private

  # Remove node from its current position
  def remove_node(node)
    node.prev.next = node.next
    node.next.prev = node.prev
  end

  # Add node to front (right after head)
  def add_to_front(node)
    node.next = @head.next
    node.prev = @head
    @head.next.prev = node
    @head.next = node
  end

  # Move existing node to front
  def move_to_front(node)
    remove_node(node)
    add_to_front(node)
  end

  # Evict least recently used item (node before tail)
  def evict_lru
    lru_node = @tail.prev
    return if lru_node == @head  # Empty list

    remove_node(lru_node)
    @cache.delete(lru_node.key)
  end
end
