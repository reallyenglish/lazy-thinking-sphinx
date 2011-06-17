require 'thinking_sphinx/test'

module Cucumber
  module ThinkingSphinx
    class ExternalWorld
      def initialize
        ::ThinkingSphinx::Test.init
        ::ThinkingSphinx::Test.start_with_autostop
      end
    end
  end
end
