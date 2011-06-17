module ThinkingSphinx
  class Source
    module SQL
      # Generates the big SQL statement to get the data back for all the fields
      # and attributes, using all the relevant association joins.
      # 
      # Examples:
      # 
      #   source.to_sql
      #
      def to_sql(options={})
        sql = "SELECT "
        sql += "SQL_NO_CACHE " if adapter.sphinx_identifier == "mysql"
        sql += <<-SQL
#{ sql_select_clause options[:offset] }
FROM #{ @model.quoted_table_name }
  #{ all_associations.collect { |assoc| assoc.to_sql }.join(' ') }
#{ sql_where_clause(options) }
GROUP BY #{ sql_group_clause }
        SQL

        sql += " ORDER BY NULL" if adapter.sphinx_identifier == "mysql"
        sql
      end

      # Simple helper method for the query range SQL - which is a statement that
      # returns minimum and maximum id values.
      # 
      def to_sql_query_range(options={})
        return nil if @index.options[:disable_range]
        
        min_statement = adapter.convert_nulls(
          "MIN(#{quote_column(@model.primary_key_for_sphinx)})", 1
        )
        max_statement = adapter.convert_nulls(
          "MAX(#{quote_column(@model.primary_key_for_sphinx)})", 1
        )

        "SELECT #{min_statement}, #{max_statement} " +
        "FROM #{@model.quoted_table_name} "
      end

      # Simple helper method for the query info SQL - which is a statement that
      # returns the single row for a corresponding id.
      # 
      def to_sql_query_info(offset)
        "SELECT * FROM #{@model.quoted_table_name} WHERE " +
        "#{quote_column(@model.primary_key_for_sphinx)} = (($id - #{offset}) / #{ThinkingSphinx.context.indexed_models.size})"
      end

      def sql_select_clause(offset)
        unique_id_expr = ThinkingSphinx.unique_id_expression(adapter, offset)

        (
          ["#{@model.quoted_table_name}.#{quote_column(@model.primary_key_for_sphinx)} #{unique_id_expr} AS #{quote_column(@model.primary_key_for_sphinx)} "] + 
          @fields.collect     { |field|     field.to_select_sql     } +
          @attributes.collect { |attribute| attribute.to_select_sql }
        ).compact.join(", ")
      end

      def sql_where_clause(options)
        logic = []
        logic += [
          "#{@model.quoted_table_name}.#{quote_column(@model.primary_key_for_sphinx)} >= $start",
          "#{@model.quoted_table_name}.#{quote_column(@model.primary_key_for_sphinx)} <= $end"
        ] unless @index.options[:disable_range]

        logic += (@conditions || [])
        logic.empty? ? "" : "WHERE #{logic.join(' AND ')}"
      end

      def sql_group_clause
        internal_groupings = []
        if @model.column_names.include?(@model.inheritance_column)
           internal_groupings << "#{@model.quoted_table_name}.#{quote_column(@model.inheritance_column)}"
        end

        (
          ["#{@model.quoted_table_name}.#{quote_column(@model.primary_key_for_sphinx)}"] + 
          @fields.collect     { |field|     field.to_group_sql     }.compact +
          @attributes.collect { |attribute| attribute.to_group_sql }.compact +
          @groupings + internal_groupings
        ).join(", ")
      end

      def quote_column(column)
        @model.connection.quote_column_name(column)
      end

      def crc_column
        if @model.table_exists? &&
          @model.column_names.include?(@model.inheritance_column)
          
          types = types_to_crcs
          return @model.to_crc32.to_s if types.empty?
          
          adapter.case(adapter.convert_nulls(
            adapter.quote_with_table(@model.inheritance_column)),
            types_to_crcs, @model.to_crc32)
        else
          @model.to_crc32.to_s
        end
      end
      
      def internal_class_column
        if @model.table_exists? &&
          @model.column_names.include?(@model.inheritance_column)
          adapter.quote_with_table(@model.inheritance_column)
        else
          "'#{@model.name}'"
        end
      end
      
      def type_values
        @model.connection.select_values <<-SQL
SELECT DISTINCT #{@model.inheritance_column}
FROM #{@model.table_name}
        SQL
      end
      
      def types_to_crcs
        type_values.compact.inject({}) { |hash, type|
          hash[type] = type.to_crc32
          hash
        }
      end
    end
  end
end
