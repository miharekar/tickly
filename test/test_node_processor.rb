require 'helper'

class TestParserEvaluator < Test::Unit::TestCase
  include Tickly::Emitter
  
  NUKE7_SCRIPT = File.open(File.dirname(__FILE__) + "/test-data/nuke7_tracker_2tracks.nk")
  
  class Tracker4
    attr_reader :knobs
    def initialize(knobs)
      @knobs = knobs
    end
  end
  
  class NodeCaptured < RuntimeError; end
  
  def test_processes_nodes
    pe = Tickly::NodeProcessor.new
    pe.add_node_handler_class(Tracker4)
    
    assert_raise(NodeCaptured) do
      pe.parse(NUKE7_SCRIPT) do | node |
        
        assert_kind_of Tracker4, node
        assert_equal "Tracker1", node.knobs["name"]
        
        raise NodeCaptured
      end
    end
  end
end