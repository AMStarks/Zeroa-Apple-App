#!/usr/bin/env python3
"""
Basic functionality test for Zeroa project
"""

import json
import os
import sys

def test_christian_prompt_elements():
    """Test the Christian prompt elements"""
    print("🧪 Testing Christian prompt elements...")
    
    try:
        from christian_prompt_elements import create_christian_prompt, CHRISTIAN_VALUES
        
        # Test prompt creation
        prompt = create_christian_prompt("Hello Nova")
        print(f"✅ Prompt created successfully: {len(prompt)} characters")
        
        # Test Christian values
        print(f"✅ Christian values loaded: {len(CHRISTIAN_VALUES)} values")
        
        return True
    except Exception as e:
        print(f"❌ Error testing Christian prompt elements: {e}")
        return False

def test_database():
    """Test the SQLite database"""
    print("🧪 Testing database...")
    
    try:
        import sqlite3
        
        # Check if database exists
        if os.path.exists('nova_conversations.db'):
            print("✅ Database file exists")
            
            # Try to connect
            conn = sqlite3.connect('nova_conversations.db')
            cursor = conn.cursor()
            
            # Check tables
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
            tables = cursor.fetchall()
            print(f"✅ Database has {len(tables)} tables")
            
            conn.close()
            return True
        else:
            print("❌ Database file not found")
            return False
    except Exception as e:
        print(f"❌ Error testing database: {e}")
        return False

def test_model_files():
    """Test if model files exist"""
    print("🧪 Testing model files...")
    
    # Check for CoreML model
    coreml_path = "Zeroa/Data/NovaFinalModel.mlpackage"
    if os.path.exists(coreml_path):
        print(f"✅ CoreML model directory exists: {coreml_path}")
        
        # Check for manifest
        manifest_path = os.path.join(coreml_path, "Manifest.json")
        if os.path.exists(manifest_path):
            print("✅ CoreML manifest exists")
        else:
            print("❌ CoreML manifest missing")
    else:
        print(f"❌ CoreML model not found: {coreml_path}")
    
    # Check for Python models
    python_models = [
        "simple_nova_server.py",
        "phi3_server_optimized.py",
        "phi3_server_robust.py"
    ]
    
    for model in python_models:
        if os.path.exists(model):
            print(f"✅ Python model exists: {model}")
        else:
            print(f"❌ Python model missing: {model}")

def test_xcode_project():
    """Test Xcode project structure"""
    print("🧪 Testing Xcode project...")
    
    # Check project file
    if os.path.exists("Zeroa.xcodeproj/project.pbxproj"):
        print("✅ Xcode project file exists")
    else:
        print("❌ Xcode project file missing")
    
    # Check source directory
    if os.path.exists("Zeroa/"):
        print("✅ Source directory exists")
        
        # Count Swift files
        swift_files = []
        for root, dirs, files in os.walk("Zeroa/"):
            for file in files:
                if file.endswith('.swift'):
                    swift_files.append(os.path.join(root, file))
        
        print(f"✅ Found {len(swift_files)} Swift files")
        
        if len(swift_files) == 0:
            print("⚠️  No Swift files found - this may indicate an issue")
    else:
        print("❌ Source directory missing")

def main():
    """Run all tests"""
    print("🚀 Starting Zeroa project functionality test...\n")
    
    tests = [
        test_christian_prompt_elements,
        test_database,
        test_model_files,
        test_xcode_project
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
        print()
    
    print(f"📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Zeroa project is working correctly.")
    else:
        print("⚠️  Some tests failed. Please check the issues above.")
    
    return passed == total

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1) 