# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAI Strict Mode Compatibility" do
  describe "nested objects with optional fields" do
    it "includes all property keys in required array for inline nested objects" do
      schema_class = Class.new(RubyLLM::Schema) do
        boolean :has_trade_in, description: "Whether trade-in mentioned"
        object :vehicle, required: false, description: "Vehicle details" do
          string :make, description: "Vehicle brand", required: false
          string :model, description: "Vehicle model", required: false
          integer :year, description: "Model year", required: false
        end
      end

      instance = schema_class.new("TradeInSchema")
      json_output = instance.to_json_schema

      # Verify top-level schema
      expect(json_output[:schema][:strict]).to be true
      expect(json_output[:schema][:additionalProperties]).to be false
      expect(json_output[:schema][:required]).to eq([:has_trade_in])

      # Verify nested object has ALL properties in required array (OpenAI strict mode requirement)
      vehicle_schema = json_output[:schema][:properties][:vehicle]
      expect(vehicle_schema[:type]).to eq("object")
      expect(vehicle_schema[:required]).to match_array([:make, :model, :year])
      expect(vehicle_schema[:additionalProperties]).to be false
    end

    it "includes all property keys in required array when using of: SchemaClass" do
      vehicle_schema = Class.new(RubyLLM::Schema) do
        string :make, description: "Vehicle brand", required: false
        string :model, description: "Vehicle model", required: false
        integer :year, description: "Model year", required: false
      end

      trade_in_schema = Class.new(RubyLLM::Schema) do
        boolean :has_trade_in, description: "Whether trade-in mentioned"
        object :vehicle, of: vehicle_schema, required: false, description: "Vehicle details"
      end

      instance = trade_in_schema.new("TradeInSchema")
      json_output = instance.to_json_schema

      # Verify nested object has ALL properties in required array
      vehicle_obj = json_output[:schema][:properties][:vehicle]
      expect(vehicle_obj[:type]).to eq("object")
      expect(vehicle_obj[:required]).to match_array([:make, :model, :year])
      expect(vehicle_obj[:additionalProperties]).to be false
    end

    it "includes all property keys in required array for deeply nested objects" do
      schema_class = Class.new(RubyLLM::Schema) do
        object :lead do
          string :name
          object :contact do
            string :email, required: false
            string :phone, required: false
          end
          object :trade_in, required: false do
            object :vehicle do
              string :make, required: false
              string :model, required: false
            end
          end
        end
      end

      instance = schema_class.new("LeadSchema")
      json_output = instance.to_json_schema

      # Verify deeply nested objects have all properties in required array
      lead = json_output[:schema][:properties][:lead]
      contact = lead[:properties][:contact]
      expect(contact[:required]).to match_array([:email, :phone])

      trade_in = lead[:properties][:trade_in]
      vehicle = trade_in[:properties][:vehicle]
      expect(vehicle[:required]).to match_array([:make, :model])
    end

    it "includes all property keys in required array for defined schemas" do
      schema_class = Class.new(RubyLLM::Schema) do
        define :vehicle do
          string :make, required: false
          string :model, required: false
          integer :year, required: false
        end

        boolean :has_trade_in
        array :vehicles, of: :vehicle
      end

      instance = schema_class.new("MultiVehicleSchema")
      json_output = instance.to_json_schema

      # Verify $defs schema has all properties in required array
      vehicle_def = json_output[:schema]["$defs"][:vehicle]
      expect(vehicle_def[:type]).to eq("object")
      expect(vehicle_def[:required]).to match_array([:make, :model, :year])
      expect(vehicle_def[:additionalProperties]).to be false
    end
  end

  describe "recommended approach for truly optional fields" do
    it "demonstrates using anyOf with null for optional fields" do
      schema_class = Class.new(RubyLLM::Schema) do
        boolean :has_trade_in
        object :vehicle, required: false do
          # Use anyOf with null for truly optional fields in strict mode
          any_of :make do
            string description: "Vehicle brand"
            null
          end
          any_of :model do
            string description: "Vehicle model"
            null
          end
          integer :year, description: "Model year"
        end
      end

      instance = schema_class.new("OptionalFieldsSchema")
      json_output = instance.to_json_schema

      vehicle = json_output[:schema][:properties][:vehicle]
      
      # All properties (including anyOf) are in required array
      expect(vehicle[:required]).to match_array([:make, :model, :year])
      
      # Make and model can be null
      expect(vehicle[:properties][:make][:anyOf]).to include(
        hash_including(type: "string"),
        {type: "null"}
      )
      expect(vehicle[:properties][:model][:anyOf]).to include(
        hash_including(type: "string"),
        {type: "null"}
      )
    end
  end

  describe "empty nested objects" do
    it "handles nested objects with no properties" do
      schema_class = Class.new(RubyLLM::Schema) do
        string :name
        object :metadata do
          # Empty object
        end
      end

      instance = schema_class.new("EmptyNestedSchema")
      json_output = instance.to_json_schema

      metadata = json_output[:schema][:properties][:metadata]
      expect(metadata[:type]).to eq("object")
      expect(metadata[:required]).to eq([])
      expect(metadata[:properties]).to eq({})
    end
  end

  describe "compatibility with OpenAI API format" do
    it "generates schema that matches OpenAI's expected format" do
      schema_class = Class.new(RubyLLM::Schema) do
        string :customer_name, description: "Full name of the customer"
        boolean :has_trade_in, description: "Whether customer mentioned trade-in"
        object :vehicle, required: false, description: "Trade-in vehicle details" do
          string :make, description: "Vehicle manufacturer", required: false
          string :model, description: "Vehicle model name", required: false
          integer :year, description: "Vehicle year", required: false
          integer :mileage, description: "Current mileage", required: false
        end
      end

      instance = schema_class.new("TradeInExtraction", description: "Extract trade-in information from customer inquiry")
      json_output = instance.to_json_schema

      # Verify the structure matches OpenAI's format
      expect(json_output).to include(
        name: "TradeInExtraction",
        description: "Extract trade-in information from customer inquiry",
        schema: hash_including(
          type: "object",
          strict: true,
          additionalProperties: false,
          required: array_including(:customer_name, :has_trade_in)
        )
      )

      # Verify nested object structure
      vehicle = json_output[:schema][:properties][:vehicle]
      expect(vehicle).to include(
        type: "object",
        description: "Trade-in vehicle details",
        additionalProperties: false,
        required: array_including(:make, :model, :year, :mileage)
      )

      # This schema should now work with OpenAI API without the error:
      # "required is required to be supplied and to be an array including every key in properties"
    end
  end
end

