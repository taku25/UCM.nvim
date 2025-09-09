{{COPYRIGHT_HEADER}}

#pragma once

#include "CoreMinimal.h"
{{DIRECT_INCLUDES}}
#include "{{CLASS_NAME}}.generated.h"

/**
 * 
 */
USTRUCT(BlueprintType)
struct {{API_MACRO}} {{CLASS_PREFIX}}{{CLASS_NAME}} : public FSlateWidgetStyle
{
	GENERATED_BODY()

	{{CLASS_PREFIX}}{{CLASS_NAME}}();
	virtual ~{{CLASS_PREFIX}}{{CLASS_NAME}}();

	// FSlateWidgetStyle
	virtual void GetResources(TArray<const FSlateBrush*>& OutBrushes) const override;
	static const FName TypeName;
	virtual const FName GetTypeName() const override { return TypeName; };
	static const {{CLASS_PREFIX}}{{CLASS_NAME}}& GetDefault();

	// Add properties here
};
