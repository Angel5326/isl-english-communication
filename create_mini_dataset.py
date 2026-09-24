import os
import pandas as pd
from sklearn.model_selection import train_test_split

# ==============================================
# >>> CHANGE THESE TWO NAMES TO MATCH YOUR FILES <<<
SIGN_1 = 'yes'   # Replace with the exact filename (without .mp4)
SIGN_2 = 'no'    # Replace with another filename (without .mp4)
# Example: if you have 'hello.mp4' and 'thank you.mp4', type 'hello' and 'thank you'
# ==============================================

raw_folder = 'dataset/raw'
data = []

print(f"Scanning for '{SIGN_1}' and '{SIGN_2}'...")

# Scan all .mp4 files in the flat folder
for filename in os.listdir(raw_folder):
    if filename.endswith('.mp4'):
        # Remove .mp4 to get the gloss name
        gloss = filename.replace('.mp4', '').lower()
        # Only keep the two signs we want to test
        if gloss == SIGN_1 or gloss == SIGN_2:
            video_id = gloss + '_' + filename  # Create a unique ID
            data.append({
                'video_id': video_id,
                'video_path': os.path.join(raw_folder, filename),
                'gloss': gloss
            })

if len(data) == 0:
    print(f'❌ No videos found for "{SIGN_1}" or "{SIGN_2}".')
    print('Please check the filenames in dataset/raw/ and update SIGN_1/SIGN_2.')
    exit()

df = pd.DataFrame(data)

# 2. Split strictly by video ID (NO DATA LEAKAGE!)
train_val, test = train_test_split(df, test_size=0.2, random_state=42, stratify=df['gloss'])
train, val = train_test_split(train_val, test_size=0.2, random_state=42, stratify=train_val['gloss'])

df['split'] = 'unknown'
df.loc[train.index, 'split'] = 'train'
df.loc[val.index, 'split'] = 'val'
df.loc[test.index, 'split'] = 'test'

# 3. Save the mini metadata
os.makedirs('dataset/metadata', exist_ok=True)
df.to_csv('dataset/metadata/metadata.csv', index=False)
print(f'✅ Mini dataset created with {len(df)} videos:')
print(df['gloss'].value_counts())
print("\nFile saved to: dataset/metadata/metadata.csv")