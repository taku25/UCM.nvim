{{COPYRIGHT_HEADER}}

#pragma once

#include "CoreMinimal.h"
{{DIRECT_INCLUDES}}

/**
 * 
 */
class {{API_MACRO}} {{CLASS_PREFIX}}{{CLASS_NAME}} : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS({{CLASS_PREFIX}}{{CLASS_NAME}})
		{}
	SLATE_END_ARGS()

	/** Constructs this widget with InArgs */
	void Construct(const FArguments& InArgs);
};
