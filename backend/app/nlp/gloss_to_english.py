import re

class GlossToEnglish:
    """
    Convert ISL gloss sequence to natural English sentence.
    ISL word order: Subject + Object + Verb (SOV)
    English word order: Subject + Verb + Object (SVO)
    """
    def __init__(self):
        # Subject mapping
        self.subject_map = {
            "I": "I", "ME": "I",
            "YOU": "you", "U": "you",
            "HE": "he", "SHE": "she",
            "WE": "we", "THEY": "they"
        }
        
        # Verb tense mapping
        self.verb_map = {
            "GO": ("go", "went", "will go"),
            "EAT": ("eat", "ate", "will eat"),
            "DRINK": ("drink", "drank", "will drink"),
            "COME": ("come", "came", "will come"),
            "SEE": ("see", "saw", "will see"),
            "WANT": ("want", "wanted", "will want"),
            "LIKE": ("like", "liked", "will like"),
            "HAVE": ("have", "had", "will have"),
            "MAKE": ("make", "made", "will make"),
            "TEACH": ("teach", "taught", "will teach"),
            "LEARN": ("learn", "learned", "will learn"),
        }
        
        # Time indicators
        self.time_map = {
            "TOMORROW": "tomorrow",
            "YESTERDAY": "yesterday",
            "TODAY": "today",
            "NOW": "now",
            "LATER": "later",
            "SOON": "soon",
            "EVERYDAY": "every day",
            "EVERY WEEK": "every week",
        }

    def translate(self, gloss_sequence):
        """
        Input: "I GO CHURCH TOMORROW"
        Output: "I will go to church tomorrow."
        """
        words = gloss_sequence.strip().upper().split()
        if not words:
            return ""
        
        # Step 1: Identify parts
        subject = None
        verb = None
        objects = []
        time = None
        
        for w in words:
            if w in self.subject_map:
                subject = self.subject_map[w]
            elif w in self.verb_map:
                verb = w
            elif w in self.time_map:
                time = self.time_map[w]
            else:
                # Check if it's a common noun or object
                objects.append(w.lower())
        
        # Step 2: Build English sentence
        if subject is None:
            subject = "I"  # Default subject
        
        # Verb with tense (default: future with "will")
        if verb:
            verb_parts = self.verb_map.get(verb, (verb.lower(), verb.lower() + "ed", "will " + verb.lower()))
            verb_phrase = verb_parts[2]  # Default to future tense
        else:
            verb_phrase = "is"
        
        # Objects with proper prepositions
        object_phrase = " ".join(objects)
        if object_phrase:
            # Add "to" for places like church, school, home
            place_words = ["church", "school", "home", "office", "market", "temple", "mosque"]
            for place in place_words:
                if place in object_phrase:
                    object_phrase = "to " + object_phrase
                    break
        
        # Time placement (usually at the end)
        time_phrase = f" {time}" if time else ""
        
        # Build final sentence
        if subject and verb_phrase and object_phrase:
            sentence = f"{subject} {verb_phrase} {object_phrase}{time_phrase}."
        elif subject and verb_phrase:
            sentence = f"{subject} {verb_phrase}{time_phrase}."
        else:
            sentence = f"{subject} {object_phrase}{time_phrase}."
        
        # Capitalize
        return sentence.capitalize()

# Example
if __name__ == "__main__":
    translator = GlossToEnglish()
    print(translator.translate("I GO CHURCH TOMORROW"))  # I will go to church tomorrow.
    print(translator.translate("ME EAT FOOD NOW"))       # I will eat food now.