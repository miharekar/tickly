require 'stringio'
require 'bychar'

module Tickly
  
  
  # Since you parse char by char, you will likely call
  # eof? on each iteration. Instead. allow it to raise and do not check.
  # This takes the profile time down from 36 seconds to 30 seconds
  # for a large file.
  class EOFError < RuntimeError  #:nodoc: all
  end
  
  class W < Bychar::Reader  #:nodoc: all
    def read_one_byte
      cache if @buf.eos?
      raise EOFError if @buf.eos?
        
      @buf.getch
    end
  end
  
  # Simplistic, incomplete and most likely incorrect TCL parser
  class Parser
    
    # Parses a piece of TCL and returns it converted into internal expression
    # structures. A basic TCL expression is just an array of Strings. An expression
    # in curly braces will have the symbol :c tacked onto the beginning of the array.
    # An expression in square braces will have :b at the beginning.
    def parse(io_or_str)
      bare_io = io_or_str.respond_to?(:read) ? io_or_str : StringIO.new(io_or_str)
      # Wrap the IO in a Bychar buffer to read faster
      reader = W.new(bare_io)
      sub_parse(reader)
    end
    
    # Override this to remove any unneeded subexpressions Modify the passed expr
    # array in-place.
    def expand_subexpr!(expr, at_depth)
    end
    
    private
    
    LAST_CHAR = -1..-1 # If we were 1.9 only we could use -1
    TERMINATORS = ["\n", ";"]
    ESC = 92.chr # Backslash (\)
    
    # Parse from a passed IO object either until an unescaped stop_char is reached
    # or until the IO is exhausted. The last argument is the class used to
    # compose the subexpression being parsed. The subparser is reentrant and not
    # destructive for the object containing it.
    def sub_parse(io, stop_char = nil, stack_depth = 0)
      # A standard stack is an expression that does not evaluate to a string
      stack = []
      buf = ''
      last_char_was_linebreak = false
      
      no_eof do
        char = io.read_one_byte
      
        if buf[LAST_CHAR] != ESC
          if char == stop_char # Bail out of a subexpr
            stack << buf if (buf.length > 0)
            # Chip away the tailing linebreak if it's there
            chomp!(stack)
            return stack
          elsif char == " " || char == "\n" # Space
            if buf.length > 0
              stack << buf
              buf = ''
            end
            if TERMINATORS.include?(char) # Introduce a stack separator! This is a new line
              if stack.any? && !last_char_was_linebreak
                last_char_was_linebreak = true
                stack = handle_expr_terminator(stack, stack_depth)
              end
            end
          elsif char == '[' # Opens a new string expression
            stack << buf if (buf.length > 0)
            last_char_was_linebreak = false
            stack << [:b] + sub_parse(io, ']', stack_depth + 1)
          elsif char == '{' # Opens a new literal expression  
            stack << buf if (buf.length > 0)
            last_char_was_linebreak = false
            stack << [:c] + sub_parse(io, '}', stack_depth + 1)
          elsif char == '"'
            stack << buf if (buf.length > 0)
            last_char_was_linebreak = false
            stack << parse_str(io, '"')
          elsif char == "'"
            stack << buf if (buf.length > 0)
            last_char_was_linebreak = false
            stack << parse_str(io, "'")
          else
            last_char_was_linebreak = false
            buf << char
          end
        else
          last_char_was_linebreak = false
          buf << char
        end
      end
    
      # Ramass any remaining buffer contents
      stack << buf if (buf.length > 0)
      
      # Handle any remaining subexpressions
      if stack.include?(nil)
        stack = handle_expr_terminator(stack, stack_depth)
      end
      # Chip awiy the trailing null
      chomp!(stack)
      
      return stack
    end
    
    def chomp!(stack)
      stack.delete_at(-1) if stack.any? && stack[-1].nil?
    end
    
    def handle_expr_terminator(stack, stack_depth)
      # Figure out whether there was a previous expr terminator
      previous_i = stack.index(nil)
      # If there were none, just get this over with. Wrap the stack contents
      # into a subexpression and carry on.
      unless previous_i
        subexpr = stack
        expand_subexpr!(subexpr, stack_depth + 1)
        return [subexpr] + [nil]
      end
      
      # Now, if there was one, we are the next subexpr in line that just terminated.
      # What we need to do is pick out all the elements from that terminator onwards
      # and wrap them.
      subexpr = stack[previous_i+1..-1]
      
      # Use expand_subexpr! to trim away any fat that we don't need
      expand_subexpr!(subexpr, stack_depth + 1)
      
      return stack[0...previous_i] + [subexpr] + [nil]
    end
    
    def no_eof(&blk)
      begin
        loop(&blk)
      rescue EOFError
      end
    end
    
    def parse_str(io, stop_char)
      buf = ''
      no_eof do
        c = io.read_one_byte
        if c == stop_char && buf[LAST_CHAR] != ESC
          return buf
        elsif buf[LAST_CHAR] == ESC # Eat out the escape char
          buf = buf[0..-2] # Trim the escape character at the end of the buffer
          buf << c
        else
          buf << c
        end
      end
      
      return buf
    end
    
  end
end