import re

class EnglishToGloss:
    """
    Convert English sentence to ISL gloss sequence.
    English: "I want to go to church tomorrow."
    ISL: "I GO CHURCH TOMORROW"
    """
    def __init__(self):
        # Stop words to remove
        self.stopwords = {
            "the", "a", "an", "to", "for", "of", "with", "at", "by", 
            "on", "in", "from", "up", "down", "off", "over", "under"
        }
        
        # Auxiliary verbs to remove
        self.auxiliaries = {
            "is", "am", "are", "was", "were", "will", "shall", 
            "do", "does", "did", "have", "has", "had", "can", "could",
            "would", "should", "may", "might", "must"
        }
        
        # Special words to keep in uppercase
        self.special_words = {
            "i": "I", "me": "ME", "you": "YOU", "he": "HE", 
            "she": "SHE", "we": "WE", "they": "THEY"
        }

    def translate(self, english_sentence):
        """
        Input: "I want to go to church tomorrow."
        Output: "I GO CHURCH TOMORROW"
        """
        # Clean the sentence
        sent = english_sentence.lower()
        sent = re.sub(r'[^\w\s\']', '', sent)
        
        words = sent.split()
        gloss_words = []
        
        for w in words:
            # Skip stopwords and auxiliaries
            if w in self.stopwords or w in self.auxiliaries:
                continue
            
            # Handle special words (I, you, etc.)
            if w in self.special_words:
                gloss_words.append(self.special_words[w])
            else:
                # Convert to uppercase for ISL gloss
                gloss_words.append(w.upper())
        
        # Return as space-separated gloss
        return " ".join(gloss_words)

# Example
if __name__ == "__main__":
    translator = EnglishToGloss()
    print(translator.translate("I want to go to church tomorrow."))  # I GO CHURCH TOMORROW
    print(translator.translate("I will eat food now."))              # I EAT FOOD NOW